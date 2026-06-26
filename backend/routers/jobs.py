# --- Módulo: jobs ---
# Endpoints de jobs de análise (pipeline static/dynamic/both).

from __future__ import annotations

import hashlib
import json
import logging
import uuid
from dataclasses import dataclass
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import PlainTextResponse

import config
import job_store
from i18n import current_lang, resolve_lang, t
from analysis_jobs import (
    AnalysisType,
    JobStatus,
    create_job,
    get_job_payload,
)
from artifact_naming import short_filename, short_stem
from modules.pseudo_c_highlighter import realign_flagged_functions_for_payload
from observability import increment
from upload_security import get_max_upload_bytes

from .deps import (
    ALLOWED_UPLOAD_EXTENSIONS,
    check_content_length,
    get_job_output_dir,
    read_upload_bytes,
    require_api_token,
    require_valid_job_id,
    sanitize_upload_name,
    summarize_dynamic_report,
)
from .schemas import DynamicAnalysisUpload, StaticAnalysisUpload

logger = logging.getLogger("rat_analyzer_api")

router = APIRouter(tags=["jobs"])


@dataclass
class _UploadJobContext:
    job_id: str
    existing_row: dict | None


# --- Validação de status de upload estático/dinâmico ---
def _parse_upload_job_status(status_raw: str | None) -> JobStatus:
    normalized = (status_raw or "completed").strip().lower()
    allowed = {JobStatus.RUNNING.value, JobStatus.COMPLETED.value, JobStatus.FAILED.value}
    if normalized not in allowed:
        raise HTTPException(400, "status inválido (use running, completed ou failed).")
    return JobStatus(normalized)


# --- Resolução ou criação de job para upload estático/dinâmico ---
def _resolve_upload_job(
    job_id_raw: str | None,
    *,
    default_file_name: str,
    analysis_type: AnalysisType,
    file_name: str,
    sha_extra: str = "",
) -> _UploadJobContext:
    if job_id_raw:
        job_id = require_valid_job_id(job_id_raw.strip())
        existing_row = job_store.get_job_row(job_id)
        if not existing_row:
            raise HTTPException(404, t("job_not_found", current_lang()))
        return _UploadJobContext(job_id=job_id, existing_row=existing_row)

    job_id = str(uuid.uuid4())
    resolved_name = file_name or default_file_name
    h = hashlib.sha256()
    h.update(resolved_name.encode("utf-8", "ignore"))
    if sha_extra:
        h.update(sha_extra.encode("utf-8", "ignore"))
    job_store.insert_job(
        job_id=job_id,
        analysis_type=analysis_type.value,
        file_name=resolved_name,
        sha256=h.hexdigest(),
        status=JobStatus.QUEUED.value,
    )
    return _UploadJobContext(job_id=job_id, existing_row=None)


# --- Tipo de análise após upload (promove para both quando há resultado irmão) ---
def _resolve_merged_analysis_type(
    job_id: str,
    existing_row: dict | None,
    *,
    default_type: str,
    sibling_result_key: str,
) -> str:
    if existing_row and existing_row.get(sibling_result_key):
        job_store.update_analysis_type(job_id, AnalysisType.BOTH.value)
        return AnalysisType.BOTH.value
    if existing_row:
        return existing_row.get("analysisType") or default_type
    return default_type


# --- Diretório de saída do job (cria se necessário) ---
def _ensure_job_output_dir(job_id: str) -> Path:
    out_dir = get_job_output_dir(job_id)
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir


# --- Escrita segura de artefacto de texto no disco ---
def _write_text_artifact(path: Path, content: str, *, job_id: str, artifact_label: str) -> None:
    try:
        path.write_text(content, encoding="utf-8", errors="replace")
    except OSError:
        logger.warning("Falha ao guardar artefato %s para job_id=%s", artifact_label, job_id)


# --- Gravação de artefactos estáticos (report, C, IL) ---
def _write_static_artifact_files(
    out_dir: Path,
    *,
    base_name: str,
    report: str,
    c_code: str,
    il_code: str,
    job_id: str,
) -> tuple[Path, Path, Path]:
    report_path = out_dir / short_filename(base_name, "report", ext="txt")
    c_code_path = out_dir / short_filename(base_name, "c", ext="txt")
    il_code_path = out_dir / short_filename(base_name, "il", ext="txt")
    for path_obj, content in (
        (report_path, report),
        (c_code_path, c_code),
        (il_code_path, il_code),
    ):
        _write_text_artifact(path_obj, content, job_id=job_id, artifact_label=path_obj.name)
    return report_path, c_code_path, il_code_path


# --- Extração de snippets de ofuscação a partir do pseudo-C ---
def _extract_obfuscation_snippets(
    c_code: str,
    *,
    c_code_path: Path,
    out_dir: Path,
    base_name: str,
    job_id: str,
    log_context: str,
) -> tuple[str, str, dict[str, int]]:
    from modules.deobfuscator import Deobfuscator
    from modules.obfuscation_snippet_extractor import extract_and_write_snippets_from_content

    if not c_code.strip():
        return "", "", {}
    try:
        deob = Deobfuscator()
        return extract_and_write_snippets_from_content(
            content=c_code,
            source_path=str(c_code_path),
            output_dir=out_dir,
            stem=base_name,
            deobfuscate_fn=deob.deobfuscate_content,
        )
    except Exception:
        logger.exception("Falha ao extrair snippets de ofuscação em %s (job_id=%s).", log_context, job_id)
        return "", "", {}


# --- Submissão de job de análise (static/dynamic/both) ---
@router.post("/api/analysis", dependencies=[Depends(require_api_token)])
async def submit_analysis(
    request: Request,
    file: UploadFile = File(...),
    analysis_type: AnalysisType = Query(
        AnalysisType.STATIC,
        description="Tipo de análise: static, dynamic ou both.",
    ),
) -> dict:
    increment("rat_analyzer_jobs_submitted_total")
    name = sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    check_content_length(request, max_bytes)

    try:
        contents = await read_upload_bytes(file, max_bytes)
    except HTTPException:
        raise
    except Exception:  # noqa: BLE001
        logger.exception("Erro ao ler upload de %s", name)
        raise HTTPException(500, "Erro ao ler o ficheiro enviado.")

    logger.info("Pedido /api/analysis recebido: file=%s analysis_type=%s", name, analysis_type.value)
    job = create_job(name, contents, analysis_type)
    logger.info(
        "Job de análise submetido: id=%s type=%s status=%s",
        job.id,
        job.analysis_type.value,
        job.status.value,
    )
    return {
        "jobId": job.id,
        "analysisType": job.analysis_type.value,
        "status": job.status.value,
    }


# --- Publicação de resultado estático (Caminho B / WPF) ---
@router.post("/api/analysis/upload_static", dependencies=[Depends(require_api_token)])
async def upload_static_analysis(payload: StaticAnalysisUpload) -> dict:
    increment("rat_analyzer_upload_static_total")

    job_status = _parse_upload_job_status(payload.status)
    ctx = _resolve_upload_job(
        payload.jobId,
        default_file_name="static_analysis",
        analysis_type=AnalysisType.STATIC,
        file_name=payload.fileName,
    )
    job_id = ctx.job_id
    existing_row = ctx.existing_row

    file_name = payload.fileName or (existing_row.get("fileName") if existing_row else "") or "analysis"

    if job_status == JobStatus.RUNNING:
        static_result = {
            "report": "",
            "cCode": "",
            "ilCode": "",
            "fileName": file_name,
            "riskScore": 0,
            "riskLevel": "",
            "flaggedIndicators": [],
            "flaggedFunctions": [],
            "staticProgress": float(payload.staticProgress or 0),
        }
        job_store.update_results(job_id, static_result, None)
        analysis_type = _resolve_merged_analysis_type(
            job_id,
            existing_row,
            default_type=AnalysisType.STATIC.value,
            sibling_result_key="dynamicResult",
        )
        job_store.update_status(job_id, JobStatus.RUNNING.value, error=None)
        logger.info("Estática em curso via upload_static: job_id=%s progress=%s", job_id, payload.staticProgress)
        return {"jobId": job_id, "analysisType": analysis_type, "status": JobStatus.RUNNING.value}

    logger.info(
        "Pedido /api/analysis/upload_static: file=%s score=%s level=%s job_id=%s",
        payload.fileName,
        payload.riskScore,
        payload.riskLevel,
        job_id,
    )

    out_dir = _ensure_job_output_dir(job_id)
    base_name = short_stem(Path(file_name).stem or "analysis")
    report_path, c_code_path, il_code_path = _write_static_artifact_files(
        out_dir,
        base_name=base_name,
        report=payload.report or "",
        c_code=payload.cCode or "",
        il_code=payload.ilCode or "",
        job_id=job_id,
    )

    c_code = payload.cCode or ""
    obf_snippets, obf_snippets_deob, obf_summary = _extract_obfuscation_snippets(
        c_code,
        c_code_path=c_code_path,
        out_dir=out_dir,
        base_name=base_name,
        job_id=job_id,
        log_context="upload_static",
    )

    obfuscation_indicator_count = int(sum(obf_summary.values())) if obf_summary else 0
    flagged_functions = realign_flagged_functions_for_payload(c_code, payload.flaggedFunctions or [])

    static_result = {
        "report": payload.report or "",
        "cCode": c_code,
        "ilCode": payload.ilCode or "",
        "fileName": file_name,
        "riskScore": int(payload.riskScore or 0),
        "riskLevel": payload.riskLevel or "",
        "flaggedIndicators": payload.flaggedIndicators or [],
        "flaggedFunctions": flagged_functions,
        "obfuscatedSnippetsFile": obf_snippets,
        "obfuscatedSnippetsDeobfuscatedFile": obf_snippets_deob,
        "obfuscationIndicatorCount": obfuscation_indicator_count,
        "staticProgress": 100.0,
    }

    last_analysis_payload = {
        "target_file": file_name,
        "report_path": str(report_path),
        "decompiled_c_file": str(c_code_path),
        "disassembly_file": str(il_code_path),
        "flagged_indicators": payload.flaggedIndicators or [],
        "flagged_functions": flagged_functions,
        "obfuscated_snippets_file": obf_snippets,
        "obfuscated_snippets_deobfuscated_file": obf_snippets_deob,
        "obfuscated_snippets_pseudoc_file": "",
        "obfuscated_snippets_deobfuscated_pseudoc_file": "",
        "obfuscation_snippets_summary": obf_summary,
        "obfuscation_indicators": [],
    }
    try:
        (out_dir / "last_analysis.json").write_text(
            json.dumps(last_analysis_payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
            errors="replace",
        )
    except OSError:
        logger.warning("Falha ao guardar last_analysis.json para job_id=%s", job_id)

    job_store.update_results(job_id, static_result, None)

    analysis_type = _resolve_merged_analysis_type(
        job_id,
        existing_row,
        default_type=AnalysisType.STATIC.value,
        sibling_result_key="dynamicResult",
    )

    if job_status == JobStatus.FAILED:
        job_store.update_status(job_id, JobStatus.FAILED.value, error=payload.error)
        final_status = JobStatus.FAILED.value
    else:
        # *Não fechar o job enquanto a VM ainda está em curso (ex.: estática termina primeiro)*
        existing_status = (
            (existing_row.get("status") if existing_row else "") or ""
        ).lower()
        vm_still_active = existing_status in (
            JobStatus.RUNNING.value,
            JobStatus.QUEUED.value,
        )
        if vm_still_active:
            job_store.update_status(job_id, JobStatus.RUNNING.value, error=None)
            final_status = JobStatus.RUNNING.value
        else:
            job_store.update_status(job_id, JobStatus.COMPLETED.value, error=None)
            final_status = JobStatus.COMPLETED.value

    logger.info("Resultado estático publicado: job_id=%s file=%s", job_id, file_name)
    return {"jobId": job_id, "analysisType": analysis_type, "status": final_status}


# --- Publicação de resultado dinâmico (Caminho B / PowerShell Hyper-V) ---
@router.post("/api/analysis/upload_dynamic", dependencies=[Depends(require_api_token)])
async def upload_dynamic_analysis(payload: DynamicAnalysisUpload) -> dict:
    increment("rat_analyzer_upload_dynamic_total")

    job_status = _parse_upload_job_status(payload.status)
    ctx = _resolve_upload_job(
        payload.jobId,
        default_file_name="dynamic_analysis",
        analysis_type=AnalysisType.DYNAMIC,
        file_name=payload.fileName,
        sha_extra=payload.runId or "",
    )
    job_id = ctx.job_id
    existing_row = ctx.existing_row

    out_dir = _ensure_job_output_dir(job_id)
    report_text = payload.report or ""

    if report_text.strip() and job_status == JobStatus.COMPLETED:
        base_name = short_stem(
            Path((payload.fileName or (existing_row.get("fileName") if existing_row else "")) or "analysis").stem
            or "analysis"
        )
        report_path = out_dir / short_filename(base_name, "dynamic_report", ext="txt")
        _write_text_artifact(report_path, report_text, job_id=job_id, artifact_label="dynamic_report.txt")

    summary = payload.dynamicSummary or summarize_dynamic_report(report_text)
    dynamic_result = {
        "report": "",
        "cCode": "",
        "ilCode": "",
        "fileName": payload.fileName or (existing_row.get("fileName") if existing_row else ""),
        "dynamicReportText": report_text,
        "dynamicSummary": summary,
        "runId": payload.runId,
        "source": "hyperv_powershell",
    }

    job_store.update_results(job_id, None, dynamic_result)

    analysis_type = _resolve_merged_analysis_type(
        job_id,
        existing_row,
        default_type=AnalysisType.DYNAMIC.value,
        sibling_result_key="staticResult",
    )

    job_store.update_status(
        job_id,
        job_status.value,
        error=payload.error if job_status == JobStatus.FAILED else None,
    )

    logger.info(
        "Resultado dinâmico publicado: job_id=%s status=%s type=%s runId=%s",
        job_id,
        job_status.value,
        analysis_type,
        payload.runId,
    )
    return {"jobId": job_id, "analysisType": analysis_type, "status": job_status.value}


# --- Artefacto de trechos obfuscados (obfuscated ou deobfuscated) ---
@router.get("/api/analysis/{job_id}/artifacts/obfuscated_snippets", response_class=PlainTextResponse)
async def get_obfuscated_snippets_artifact(
    job_id: str,
    variant: str = Query("obfuscated", description="obfuscated ou deobfuscated"),
) -> PlainTextResponse:
    require_valid_job_id(job_id)
    out_dir = get_job_output_dir(job_id)
    last_path = out_dir / "last_analysis.json"
    if not last_path.exists():
        raise HTTPException(404, "Job ou ficheiro de análise não encontrado.")
    try:
        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)
    except Exception:
        raise HTTPException(500, "Erro ao ler resultados do job.")

    if variant == "obfuscated":
        path_str = last.get("obfuscated_snippets_file") or last.get("obfuscated_snippets_pseudoc_file") or ""
    elif variant == "deobfuscated":
        path_str = (
            last.get("obfuscated_snippets_deobfuscated_file")
            or last.get("obfuscated_snippets_deobfuscated_pseudoc_file")
            or ""
        )
    else:
        raise HTTPException(400, "variant deve ser 'obfuscated' ou 'deobfuscated'.")

    if path_str:
        artifact_path = Path(path_str).resolve()
        out_dir_resolved = out_dir.resolve()
        if out_dir_resolved not in artifact_path.parents and artifact_path != out_dir_resolved:
            raise HTTPException(403, "Path inválido.")
        if artifact_path.exists():
            try:
                content = artifact_path.read_text(encoding="utf-8", errors="replace")
                return PlainTextResponse(content=content, media_type="text/plain; charset=utf-8")
            except OSError:
                raise HTTPException(500, "Erro ao ler ficheiro.")

    try:
        payload_data = get_job_payload(job_id) or {}
        static_result = payload_data.get("staticResult") if isinstance(payload_data, dict) else {}
        if isinstance(static_result, dict):
            c_code = static_result.get("cCode") or ""
            file_name = static_result.get("fileName") or "analysis"
            if isinstance(c_code, str) and c_code.strip():
                from modules.deobfuscator import Deobfuscator
                from modules.obfuscation_snippet_extractor import extract_and_write_snippets_from_content

                stem = short_stem(Path(str(file_name)).stem or "analysis")
                deob = Deobfuscator()
                obf_path, deob_path, _summary = extract_and_write_snippets_from_content(
                    content=c_code,
                    source_path=str(out_dir / f"{stem}.c.txt"),
                    output_dir=out_dir,
                    stem=stem,
                    deobfuscate_fn=deob.deobfuscate_content,
                )
                rebuilt = obf_path if variant == "obfuscated" else deob_path
                if rebuilt:
                    rebuilt_path = Path(rebuilt).resolve()
                    out_dir_resolved = out_dir.resolve()
                    if out_dir_resolved in rebuilt_path.parents and rebuilt_path.exists():
                        content = rebuilt_path.read_text(encoding="utf-8", errors="replace")
                        return PlainTextResponse(content=content, media_type="text/plain; charset=utf-8")
    except Exception:
        logger.exception("Fallback de reconstrução de snippets falhou para job_id=%s", job_id)

    indicators = last.get("obfuscation_indicators") or []
    if not indicators and last.get("report_path"):
        try:
            out_dir_resolved = out_dir.resolve()
            report_path = Path(last["report_path"]).resolve()
            if report_path.exists() and (
                out_dir_resolved in report_path.parents or report_path.parent == out_dir_resolved
            ):
                report_text = report_path.read_text(encoding="utf-8", errors="replace")
                in_section = False
                for line in report_text.splitlines():
                    if "Indicadores de Ofuscação" in line or "Indicadores de ofuscação" in line:
                        in_section = True
                        continue
                    if in_section:
                        if not line.strip():
                            break
                        if line.strip().startswith("- "):
                            indicators.append(line.strip()[2:].strip())
                        elif line.strip().startswith("  - "):
                            indicators.append(line.strip()[4:].strip())
        except Exception:
            pass

    if indicators:
        lines = [
            "Indicadores de ofuscação detetados no binário (categoria de risco Obfuscation):",
            f"Total: {len(indicators)} ocorrência(s)",
            "",
        ]
        for i, ind in enumerate(indicators, 1):
            lines.append(f"  {i}. {ind}")
        lines.append("")
        lines.append(t("snippets_note", current_lang()))
        return PlainTextResponse(content="\n".join(lines), media_type="text/plain; charset=utf-8")

    raise HTTPException(404, t("snippets_not_available", current_lang()))


# --- Consulta de estado e payload de um job ---
@router.get("/api/analysis/{job_id}")
async def get_analysis_status(job_id: str) -> dict:
    require_valid_job_id(job_id)
    logger.info("Pedido /api/analysis/%s recebido.", job_id)
    payload = get_job_payload(job_id)
    if not payload:
        logger.warning("Pedido /api/analysis/%s: job não encontrado.", job_id)
        raise HTTPException(404, t("job_not_found", current_lang()))
    logger.info(
        "Pedido /api/analysis/%s: devolvido status=%s analysisType=%s",
        job_id,
        payload.get("status"),
        payload.get("analysisType"),
    )
    return payload


# --- Listagem paginada de análises ---
@router.get("/api/analyses")
async def list_analyses(limit: int = 50, offset: int = 0) -> dict:
    limit = min(max(1, limit), 200)
    offset = max(0, offset)
    try:
        items = job_store.list_jobs(limit=limit, offset=offset)
        return {"items": items, "limit": limit, "offset": offset}
    except Exception:  # noqa: BLE001
        logger.exception("Erro ao listar análises (limit=%s, offset=%s)", limit, offset)
        raise HTTPException(500, t("list_jobs_error", current_lang()))
