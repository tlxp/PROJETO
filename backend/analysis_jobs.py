# --- Módulo: analysis_jobs ---
# --- Gestão de jobs de análise estática/dinâmica (memória + SQLite) ---

from __future__ import annotations

import enum
import json
import logging
import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field, fields, asdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import config
from c_code_payload import (
    MAX_CCODE_CHARS,
    compose_fallback_descompilation_ccode,
    should_compose_decompilation_fallback,
    summarize_c_code_payload,
)
from modules.pseudo_c_highlighter import realign_flagged_functions_for_payload
from rat_analyzer import RATAnalyzer
from vm_orchestrator import run_dynamic_analysis
import job_store
from i18n import current_lang, t
from pipeline_version import compute_pipeline_version
from task_queue import is_queue_enabled, get_queue
from upload_security import resolve_safe_path, sanitize_upload_filename


# --- Tipos de análise suportados ---
class AnalysisType(str, enum.Enum):
    STATIC = "static"
    DYNAMIC = "dynamic"
    BOTH = "both"


# --- Estados possíveis de um job ---
class JobStatus(str, enum.Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


# --- Resultado serializável enviado ao frontend ---
@dataclass
class AnalysisResult:
    report: str = ""
    cCode: str = ""
    ilCode: str = ""
    fileName: str = ""
    riskScore: int = 0
    riskLevel: str = ""
    flaggedIndicators: list[str] = field(default_factory=list)
    flaggedFunctions: list[dict] = field(default_factory=list)
    obfuscatedSnippetsFile: str = ""
    obfuscatedSnippetsDeobfuscatedFile: str = ""
    obfuscationIndicatorCount: int = 0

    dynamicReport: Optional[dict] = None
    dynamicSummary: Optional[str] = None


# --- Job de análise com caminhos, estado e resultados ---
@dataclass
class AnalysisJob:
    id: str
    analysis_type: AnalysisType
    status: JobStatus = JobStatus.QUEUED
    error: Optional[str] = None

    # Caminhos base deste job
    base_dir: Path = field(default_factory=Path)
    sample_path: Path = field(default_factory=Path)
    output_dir: Path = field(default_factory=Path)

    # Resultados
    static_result: Optional[AnalysisResult] = None
    dynamic_result: Optional[AnalysisResult] = None

# --- Serialização para dicionário ---
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "analysisType": self.analysis_type.value,
            "status": self.status.value,
            "error": self.error,
            "staticResult": asdict(self.static_result) if self.static_result else None,
            "dynamicResult": asdict(self.dynamic_result) if self.dynamic_result else None,
        }


_JOBS: Dict[str, AnalysisJob] = {}
_JOBS_LOCK = threading.Lock()
_LOGGER = logging.getLogger("rat_analyzer_jobs")

# *Limites de tamanho para o pseudo-C enviado ao frontend (ver c_code_payload.py)*
_EXECUTOR: Optional[ThreadPoolExecutor] = None
_EXECUTOR_LOCK = threading.Lock()


# --- Obtém ou cria o ThreadPoolExecutor partilhado ---
def _get_executor() -> ThreadPoolExecutor:
    global _EXECUTOR
    with _EXECUTOR_LOCK:
        if _EXECUTOR is None:
            try:
                max_workers = int(os.environ.get("RATANALYZER_MAX_WORKERS", "2"))
            except ValueError:
                max_workers = 2
            max_workers = max(1, max_workers)
            _EXECUTOR = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="analysis-job")
        return _EXECUTOR


# --- Constrói AnalysisResult a partir de dict da DB (ignora chaves desconhecidas) ---
def _result_from_dict(data: object) -> Optional[AnalysisResult]:
    if not isinstance(data, dict):
        return None
    known = {f.name for f in fields(AnalysisResult)}
    try:
        return AnalysisResult(**{k: v for k, v in data.items() if k in known})
    except Exception:  # noqa: BLE001
        _LOGGER.exception("Falha ao reconstruir AnalysisResult a partir da DB.")
        return None


# --- Garante existência de sandbox_jobs ---
def _ensure_jobs_dir() -> Path:
    base = config.SANDBOX_JOBS_DIR
    base.mkdir(parents=True, exist_ok=True)
    return base


# --- Create job ---
def create_job(file_name: str, contents: bytes, analysis_type: AnalysisType) -> AnalysisJob:
    # Defesa em profundidade: mesmo que a camada API já sanitize, nunca
    # aceitar aqui nomes com separadores/`..`/paths absolutos.
    file_name = sanitize_upload_filename(file_name)
    jobs_root = _ensure_jobs_dir()
    pipeline_version = compute_pipeline_version()
    sha = job_store.sha256_bytes(contents)

    # Cache/deduplicação: reusar análise anterior quando o ficheiro é igual
    # Regras:
    #  - static pode reutilizar resultados de static/both
    #  - dynamic pode reutilizar resultados de dynamic/both (quando existirem)
    #  - both reutiliza apenas both; caso contrário faz reuso parcial no _run_job (via DB + job_store)
    # Política: criar sempre um novo job_id (compatível com UI), mas marcar reused_from_job_id
    # e copiar resultados da DB quando possível.
    wanted_types: list[str] = []
    if analysis_type == AnalysisType.STATIC:
        wanted_types = [AnalysisType.BOTH.value, AnalysisType.STATIC.value]
    elif analysis_type == AnalysisType.DYNAMIC:
        wanted_types = [AnalysisType.BOTH.value, AnalysisType.DYNAMIC.value]
    else:
        wanted_types = [AnalysisType.BOTH.value]

    job_id = str(uuid.uuid4())
    base_dir = jobs_root / job_id
    base_dir.mkdir(parents=True, exist_ok=True)

    # Garantir que o sample fica mesmo dentro do diretório do job.
    sample_path = resolve_safe_path(base_dir, file_name)
    output_dir = base_dir / "out"
    output_dir.mkdir(exist_ok=True)

    # Persistência/auditoria básica
    try:
        job_store.insert_job(
            job_id=job_id,
            analysis_type=analysis_type.value,
            file_name=file_name,
            sha256=sha,
            status=JobStatus.QUEUED.value,
        )
        job_store.update_pipeline_version(job_id, pipeline_version)
    except Exception:
        # Não falhar o pipeline por problemas de DB
        _LOGGER.exception("Falha ao registar job %s na base de dados de histórico.", job_id)

    # Tentar cache após insert (para manter audit trail do pedido)
    cached_row: Optional[dict] = None
    cached_from: Optional[str] = None
    try:
        for t in wanted_types:
            r = job_store.find_completed_by_sha256(sha256=sha, analysis_type=t, pipeline_version=pipeline_version)
            if r:
                cached_row = r
                cached_from = str(r.get("id") or "")
                break
    except Exception:
        cached_row = None
        cached_from = None

    if cached_row and cached_from:
        # Marcar como reused e preencher resultados imediatamente (sem reexecutar análises)
        try:
            job_store.mark_reused(job_id, cached_from)
            job_store.update_results(job_id, cached_row.get("staticResult"), cached_row.get("dynamicResult"))
            job_store.update_status(job_id, JobStatus.COMPLETED.value, error=None)
        except Exception:
            _LOGGER.exception("Falha ao aplicar cache para job_id=%s reused_from=%s", job_id, cached_from)
        # Não guardar o binário em disco se já temos tudo (poupa espaço).
        # Mantemos um marcador para debug local.
        try:
            (base_dir / ".reused").write_text(f"reused_from={cached_from}\nsha256={sha}\npipeline={pipeline_version}\n", encoding="utf-8")
        except Exception:
            pass

        job = AnalysisJob(
            id=job_id,
            analysis_type=analysis_type,
            status=JobStatus.COMPLETED,
            base_dir=base_dir,
            sample_path=sample_path,
            output_dir=output_dir,
            # Copiar resultados para memória: get_job_payload prefere a versão em
            # memória, e sem isto o frontend recebia um job "completed" vazio.
            static_result=_result_from_dict(cached_row.get("staticResult")),
            dynamic_result=_result_from_dict(cached_row.get("dynamicResult")),
        )
        with _JOBS_LOCK:
            _JOBS[job_id] = job
        _LOGGER.info("Job criado por cache: id=%s type=%s reused_from=%s sha256=%s", job_id, analysis_type.value, cached_from, sha)
        return job

    # Sem cache: guardar binário no job_dir
    sample_path.write_bytes(contents)

    job = AnalysisJob(
        id=job_id,
        analysis_type=analysis_type,
        status=JobStatus.QUEUED,
        base_dir=base_dir,
        sample_path=sample_path,
        output_dir=output_dir,
    )

    with _JOBS_LOCK:
        _JOBS[job_id] = job

    # Log estruturado da criação do job (visível no terminal do uvicorn).
    _LOGGER.info(
        "Job criado: id=%s type=%s file=%s sha256=%s base_dir=%s",
        job_id,
        analysis_type.value,
        file_name,
        sha or "<desconhecido>",
        base_dir,
    )

    # Se houver Redis configurado, enfileirar para worker RQ;
    # caso contrário, correr no pool de threads local (modo dev/Windows).
    if is_queue_enabled():
        q = get_queue("analysis")
        q.enqueue(_run_job, job_id)
    else:
        _get_executor().submit(_run_job, job_id)

    return job


# --- Get job ---
def get_job(job_id: str) -> Optional[AnalysisJob]:
    with _JOBS_LOCK:
        return _JOBS.get(job_id)


# --- Reconstrói AnalysisJob a partir da DB + disco (worker RQ noutro processo) ---
def _rebuild_job_from_store(job_id: str) -> Optional[AnalysisJob]:
    try:
        row = job_store.get_job_row(job_id)
    except Exception:
        _LOGGER.exception("Falha ao ler job %s da DB para reconstrução.", job_id)
        return None
    if not row:
        return None

    try:
        analysis_type = AnalysisType(str(row.get("analysisType")))
    except ValueError:
        _LOGGER.warning("analysis_type inválido na DB para job %s: %r", job_id, row.get("analysisType"))
        return None
    try:
        status = JobStatus(str(row.get("status")))
    except ValueError:
        status = JobStatus.QUEUED

    base_dir = _ensure_jobs_dir() / job_id
    file_name = str(row.get("fileName") or "")
    try:
        sample_path = resolve_safe_path(base_dir, sanitize_upload_filename(file_name))
    except ValueError:
        _LOGGER.warning("file_name inválido na DB para job %s: %r", job_id, file_name)
        return None

    job = AnalysisJob(
        id=job_id,
        analysis_type=analysis_type,
        status=status,
        base_dir=base_dir,
        sample_path=sample_path,
        output_dir=base_dir / "out",
    )
    with _JOBS_LOCK:
        _JOBS.setdefault(job_id, job)
        job = _JOBS[job_id]
    _LOGGER.info("Job %s reconstruído a partir da DB/disco (worker externo).", job_id)
    return job


# --- Executa job de análise (estático/dinâmico) ---
def _run_job(job_id: str) -> None:
    job = get_job(job_id)
    if not job:
        # Worker RQ (processo separado): reconstruir o job a partir da DB/disco.
        job = _rebuild_job_from_store(job_id)
    if not job:
        _LOGGER.warning("Tentativa de executar job inexistente: id=%s", job_id)
        return

    job.status = JobStatus.RUNNING
    try:
        job_store.update_status(job.id, JobStatus.RUNNING.value)
    except Exception:
        pass

    try:
        if job.analysis_type in (AnalysisType.STATIC, AnalysisType.BOTH):
            job.static_result = _run_static(job)

        if job.analysis_type in (AnalysisType.DYNAMIC, AnalysisType.BOTH):
            job.dynamic_result = _run_dynamic(job)

        job.status = JobStatus.COMPLETED
        try:
            job_store.update_results(
                job.id,
                asdict(job.static_result) if job.static_result else None,
                asdict(job.dynamic_result) if job.dynamic_result else None,
            )
            job_store.update_status(job.id, JobStatus.COMPLETED.value, error=None)
        except Exception:
            pass
        _LOGGER.info(
            "Job concluído com sucesso: id=%s type=%s static=%s dynamic=%s",
            job.id,
            job.analysis_type.value,
            "ok" if job.static_result is not None else "none",
            "ok" if job.dynamic_result is not None else "none",
        )
    except Exception as exc:  # noqa: BLE001
        job.status = JobStatus.FAILED
        job.error = str(exc)
        try:
            job_store.update_status(job.id, JobStatus.FAILED.value, error=job.error)
            job_store.update_results(
                job.id,
                asdict(job.static_result) if job.static_result else None,
                asdict(job.dynamic_result) if job.dynamic_result else None,
            )
        except Exception:
            pass
        _LOGGER.exception("Job falhou: id=%s type=%s error=%s", job.id, job.analysis_type.value, job.error)


# --- Payload do job: memória → DB → reconstrução a partir de last_analysis.json ---
def get_job_payload(job_id: str) -> Optional[dict]:
    j = get_job(job_id)
    if j:
        _LOGGER.info("get_job_payload: job_id=%s encontrado em memória (status=%s)", job_id, j.status.value)
        return j.to_dict()
    # 1) Tentar DB de histórico
    try:
        row = job_store.get_job_row(job_id)
        if row:
            _LOGGER.info(
                "get_job_payload: job_id=%s carregado da base de dados (status=%s)",
                job_id,
                row.get("status"),
            )
            static_result = row.get("staticResult")
            if isinstance(static_result, dict) and static_result.get("cCode"):
                static_result = dict(static_result)
                static_result["flaggedFunctions"] = realign_flagged_functions_for_payload(
                    static_result.get("cCode") or "",
                    static_result.get("flaggedFunctions") or [],
                )

            # Compatibilizar com o formato do frontend (staticResult/dynamicResult já vêm)
            return {
                "id": row["id"],
                "analysisType": row["analysisType"],
                "status": row["status"],
                "error": row.get("error"),
                "staticResult": static_result,
                "dynamicResult": row.get("dynamicResult"),
                "fileName": row.get("fileName"),
                "sha256": row.get("sha256"),
                "createdAt": row.get("createdAt"),
                "updatedAt": row.get("updatedAt"),
            }
    except Exception:
        # Se a DB falhar por qualquer motivo, continuamos para o fallback em disco.
        _LOGGER.exception("get_job_payload: falha ao obter job_id=%s da base de dados", job_id)

    # 2) Fallback: tentar reconstruir um resultado estático mínimo a partir de last_analysis.json
    try:
        base_dir = _ensure_jobs_dir() / job_id
        out_dir = base_dir / "out"
        last_path = out_dir / "last_analysis.json"
        if not last_path.exists():
            _LOGGER.warning(
                "get_job_payload: job_id=%s não encontrado em memória/DB e sem last_analysis.json em %s",
                job_id,
                last_path,
            )
            return None

        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)

        report_path = last.get("report_path")
        report_content = _read_file_safe(report_path)
        flagged_indicators = last.get("flagged_indicators") or []
        flagged_functions = last.get("flagged_functions") or []

        # Reaproveita a mesma lógica de escolha de ficheiros de _run_static,
        # mas sem voltar a correr a análise completa.
        deobf = last.get("deobfuscated_file")
        consolidated = last.get("consolidated_file")
        decompiled_c = last.get("decompiled_c_file")
        obf_snippets = (
            last.get("obfuscated_snippets_file")
            or last.get("obfuscated_snippets_pseudoc_file")
            or ""
        )
        obf_snippets_deob = (
            last.get("obfuscated_snippets_deobfuscated_file")
            or last.get("obfuscated_snippets_deobfuscated_pseudoc_file")
            or ""
        )
        obfuscation_indicators = last.get("obfuscation_indicators") or []

        c_code = ""
        if deobf:
            c_code = _read_file_safe(deobf)
        if not c_code and consolidated:
            c_code = _read_file_safe(consolidated)
        if not c_code and decompiled_c:
            c_code = _read_file_safe(decompiled_c)
        if not c_code and should_compose_decompilation_fallback(last):
            c_code = compose_fallback_descompilation_ccode(last)
        if not c_code:
            c_code = "# Código não disponível."

        summarized_c, flagged_functions = summarize_c_code_payload(
            c_code, flagged_indicators, flagged_functions
        )

        disasm = last.get("disassembly_file")
        il_code = _read_file_safe(disasm, errors="replace") if disasm else ""
        if not il_code:
            il_code = t("no_bytecode", current_lang())

        target_file = last.get("target_file") or ""
        file_name = Path(target_file).name if target_file else "output"

        static_result = {
            "report": report_content or t("report_not_generated", current_lang()),
            "cCode": summarized_c,
            "ilCode": il_code,
            "fileName": file_name,
            # Sem acesso ao resumo completo da análise antiga, não conseguimos
            # recuperar o score/nível reais; fornecemos um valor neutro.
            "riskScore": 0,
            "riskLevel": "",
            "flaggedIndicators": flagged_indicators,
            "flaggedFunctions": flagged_functions,
            "obfuscatedSnippetsFile": obf_snippets,
            "obfuscatedSnippetsDeobfuscatedFile": obf_snippets_deob,
            "obfuscationIndicatorCount": len(obfuscation_indicators),
        }

        payload = {
            "id": job_id,
            "analysisType": AnalysisType.STATIC.value,
            "status": JobStatus.COMPLETED.value,
            "error": None,
            "staticResult": static_result,
            "dynamicResult": None,
            "fileName": file_name,
            "sha256": None,
            "createdAt": None,
            "updatedAt": None,
        }
        _LOGGER.info(
            "get_job_payload: job_id=%s reconstruído a partir de last_analysis.json em %s",
            job_id,
            last_path,
        )
        return payload
    except Exception:
        _LOGGER.exception("get_job_payload: erro inesperado ao reconstruir job_id=%s a partir de disco", job_id)
        return None


# --- Análise estática via RATAnalyzer ---
def _run_static(job: AnalysisJob) -> AnalysisResult:
    ext = job.sample_path.suffix.lower()
    analyzer = RATAnalyzer(
        str(job.sample_path),
        output_dir=str(job.output_dir),
        use_dotnet_decompiler=(ext in (".exe", ".dll")),
    )
    results = analyzer.analyze()

    last_path = job.output_dir / "last_analysis.json"
    report_content = ""
    c_code = ""
    il_code = ""
    flagged_indicators: list[str] = []
    flagged_functions: list[dict] = []
    obf_snippets = ""
    obf_snippets_deob = ""

    if last_path.exists():
        import json

        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)

        report_path = last.get("report_path")
        report_content = _read_file_safe(report_path)
        flagged_indicators = last.get("flagged_indicators") or []
        flagged_functions = last.get("flagged_functions") or []
        obf_snippets = (
            last.get("obfuscated_snippets_file")
            or last.get("obfuscated_snippets_pseudoc_file")
            or ""
        )
        obf_snippets_deob = (
            last.get("obfuscated_snippets_deobfuscated_file")
            or last.get("obfuscated_snippets_deobfuscated_pseudoc_file")
            or ""
        )
        obfuscation_indicators = last.get("obfuscation_indicators") or []

        deobf = last.get("deobfuscated_file")
        consolidated = last.get("consolidated_file")
        decompiled_c = last.get("decompiled_c_file")
        if deobf:
            c_code = _read_file_safe(deobf)
        if not c_code and consolidated:
            c_code = _read_file_safe(consolidated)
        if not c_code and decompiled_c:
            c_code = _read_file_safe(decompiled_c)
        if not c_code and should_compose_decompilation_fallback(last):
            c_code = compose_fallback_descompilation_ccode(last)

        disasm = last.get("disassembly_file")
        if disasm:
            il_code = _read_file_safe(disasm, errors="replace")
        if not il_code:
            il_code = t("no_bytecode", current_lang())
    else:
        report_content = t("report_not_generated", current_lang())
        c_code = t("code_not_available", current_lang())
        il_code = t("bytecode_not_available", current_lang())

    summarized_c, flagged_functions = summarize_c_code_payload(
        c_code, flagged_indicators, flagged_functions
    )

    return AnalysisResult(
        report=report_content,
        cCode=summarized_c,
        ilCode=il_code,
        fileName=job.sample_path.name,
        riskScore=int(results.get("risk_score", 0)),
        riskLevel=str(results.get("risk_level", "")),
        flaggedIndicators=flagged_indicators,
        flaggedFunctions=flagged_functions,
        obfuscatedSnippetsFile=obf_snippets,
        obfuscatedSnippetsDeobfuscatedFile=obf_snippets_deob,
        obfuscationIndicatorCount=len(obfuscation_indicators),
    )


# --- Análise dinâmica via orquestrador de VMs ---
def _run_dynamic(job: AnalysisJob) -> AnalysisResult:
    result = run_dynamic_analysis(job)
    summary = str(result.get("summary", ""))
    dynamic_report = result.get("behavior") or {}
    # Guardar também o driver para auditoria/depuração simples.
    if "driver" in result and isinstance(dynamic_report, dict):
        dynamic_report.setdefault("driver", result.get("driver"))
    return AnalysisResult(
        fileName=job.sample_path.name,
        dynamicReport=dynamic_report,
        dynamicSummary=summary,
    )


# --- Leitura segura de ficheiro com fallback vazio ---
def _read_file_safe(path: Optional[str | Path], encoding: str = "utf-8", errors: str = "replace") -> str:
    if not path:
        return ""
    p = Path(path)
    if not p.exists():
        return ""
    try:
        with open(p, encoding=encoding, errors=errors) as f:
            return f.read()
    except Exception:  # noqa: BLE001
        return ""

