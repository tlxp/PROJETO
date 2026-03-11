"""
API REST para o RAT Analyzer.
Expõe um endpoint de upload e análise para o frontend (drop-n-analyze) e para o WPF.
"""

import os
import sys
import uuid
import tempfile
import time
import logging
from pathlib import Path
from typing import Iterable, List, Tuple

from fastapi import FastAPI, File, UploadFile, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel

# Garantir que o projeto está no path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT_ROOT))

import config
from rat_analyzer import RATAnalyzer
from analysis_jobs import AnalysisType, AnalysisJob, create_job, get_job, get_job_payload, summarize_c_code
import job_store

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("rat_analyzer_api")


app = FastAPI(title="RAT Analyzer API v2", version="1.0.0")

# CORS para o frontend React (Vite normalmente em localhost:8080 ou 5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://localhost:5173", "http://127.0.0.1:8080", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class StaticAnalysisUpload(BaseModel):
    """Payload enviado pelo WPF com um resultado de análise estática já concluído.

    Este endpoint permite que o WPF faça a análise completa primeiro (usando, por exemplo,
    /api/analyze ou /api/analyze_stream) e só depois publique o resultado final no backend
    para ser consumido pelo frontend via /api/analysis/{jobId}.
    """

    fileName: str
    report: str
    cCode: str
    ilCode: str
    riskScore: int = 0
    riskLevel: str = ""
    flaggedIndicators: list[str] | None = None
    flaggedFunctions: list[dict] | None = None


def _read_file_safe(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
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


def _normalize_indicators(flagged_indicators: Iterable[str]) -> List[str]:
    """Normaliza a lista de indicadores (trim, remove vazios/duplicados)."""
    seen = set()
    out: List[str] = []
    for raw in flagged_indicators or []:
        s = (raw or "").strip()
        if not s or s in seen:
            continue
        seen.add(s)
        out.append(s)
    return out


def _build_windows_around_indicators(lines: List[str], indicators: List[str], radius: int) -> List[Tuple[int, int]]:
    """
    Devolve intervalos de linhas [start, end] que cobrem janelas em volta de cada ocorrência
    de qualquer indicador. Usa índices 0-based.
    """
    n = len(lines)
    ranges: List[Tuple[int, int]] = []
    if n == 0 or not indicators:
        return ranges

    for indicator in indicators:
        for i, line in enumerate(lines):
            if indicator in line:
                start = max(0, i - radius)
                end = min(n - 1, i + radius)
                ranges.append((start, end))

    if not ranges:
        return []

    # Fundir intervalos sobrepostos/adjacentes
    ranges.sort()
    merged: List[Tuple[int, int]] = []
    cur_start, cur_end = ranges[0]
    for s, e in ranges[1:]:
        if s <= cur_end + 1:
            cur_end = max(cur_end, e)
        else:
            merged.append((cur_start, cur_end))
            cur_start, cur_end = s, e
    merged.append((cur_start, cur_end))
    return merged


@app.post("/api/analyze")
async def analyze_file(request: Request, file: UploadFile = File(...)):
    """
    Recebe um ficheiro (.exe, .dll, .cs), executa a análise e devolve
    relatório, código C#/C e assembly/IL para exibir no frontend.
    """
    client_host = request.client.host if request.client else "unknown"
    # Validar extensão
    name = file.filename or "file"
    ext = Path(name).suffix.lower()
    if ext not in (".exe", ".dll", ".cs"):
        logger.warning("Rejeitado ficheiro %s (%s) de %s: extensão não suportada", name, ext, client_host)
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    suffix = ext
    prefix = "rat_"
    tmp_dir = Path(tempfile.mkdtemp(prefix=prefix))
    target_path = tmp_dir / name

    logger.info("Recebido pedido /api/analyze de %s para ficheiro %s (ext=%s)", client_host, name, ext)
    try:
        contents = await file.read()
        target_path.write_bytes(contents)
    except Exception as e:
        raise HTTPException(500, f"Erro ao guardar ficheiro: {e}")

    start_time = time.perf_counter()
    try:
        # Usar diretório de saída dedicado a este pedido
        output_dir = tmp_dir / "out"
        output_dir.mkdir(exist_ok=True)

        def log_cb(msg: str) -> None:
            logger.info("[ANALYZE %s] %s", name, msg)

        analyzer = RATAnalyzer(
            str(target_path),
            output_dir=str(output_dir),
            use_dotnet_decompiler=(ext in (".exe", ".dll")),
            log_callback=log_cb,
        )
        logger.info("Iniciar análise estática para %s", target_path)
        results = analyzer.analyze()
        elapsed = time.perf_counter() - start_time
        logger.info("Análise terminada para %s em %.1f segundos (risk_score=%s, risk_level=%s)",
                    name, elapsed, results.get("risk_score"), results.get("risk_level"))
    except FileNotFoundError as e:
        logger.error("Erro FileNotFound durante análise de %s: %s", name, e)
        raise HTTPException(400, str(e))
    except Exception as e:
        logger.exception("Erro inesperado durante análise de %s", name)
        raise HTTPException(500, f"Erro na análise: {str(e)}")
    finally:
        # Limpeza: remover ficheiro temporário (opcional manter out_dir por um tempo)
        try:
            if target_path.exists():
                target_path.unlink()
        except Exception:
            pass

    # Ler last_analysis.json para obter caminhos do relatório e códigos
    last_path = output_dir / "last_analysis.json"
    report_content = ""
    c_code = ""
    il_code = ""

    flagged_indicators: list[str] = []
    flagged_functions: list[dict] = []
    if last_path.exists():
        import json
        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)
        report_path = last.get("report_path")
        report_content = _read_file_safe(report_path)
        flagged_indicators = last.get("flagged_indicators") or []
        flagged_functions = last.get("flagged_functions") or []

        # Código “C”: preferir C# descompilado (desobfuscado ou consolidado) ou pseudo-C
        deobf = last.get("deobfuscated_file")
        consolidated = last.get("consolidated_file")
        decompiled_c = last.get("decompiled_c_file")
        if deobf:
            c_code = _read_file_safe(deobf)
        if not c_code and consolidated:
            c_code = _read_file_safe(consolidated)
        if not c_code and decompiled_c:
            c_code = _read_file_safe(decompiled_c)
        if not c_code and last.get("decompilation_error_summary"):
            c_code = f"# Descompilação não disponível\n{last.get('decompilation_error_summary')}"
        # Aplicar resumo para evitar payloads gigantes no frontend
        c_code = summarize_c_code(c_code, flagged_indicators)

        # IL / Bytecode: assembly (desmontagem) ou mensagem
        disasm = last.get("disassembly_file")
        if disasm:
            il_code = _read_file_safe(disasm, errors="replace")
        if not il_code:
            il_code = "# Nenhum bytecode/assembly disponível para este ficheiro."
    else:
        report_content = "# Relatório não gerado."
        c_code = "# Código não disponível."
        il_code = "# Bytecode não disponível."

    return {
        "report": report_content,
        "cCode": c_code,
        "ilCode": il_code,
        "fileName": name,
        "riskScore": results.get("risk_score", 0),
        "riskLevel": results.get("risk_level", ""),
        "flaggedIndicators": flagged_indicators,
        # Funções suspeitas com ranges exatos no pseudo-C (quando existir pseudo-C da Ghidra).
        "flaggedFunctions": flagged_functions,
    }


@app.post("/api/analyze_stream")
async def analyze_file_stream(file: UploadFile = File(...)):
    """
    Versão com streaming: envia logs em tempo (quase) real + resultado final em NDJSON.
    Cada linha é um JSON com:
      - {"type": "log", "message": "..."}
      - {"type": "result", ...payload final...}
      - {"type": "error", "message": "..."} em caso de falha.
    """
    import json
    import queue
    import threading

    name = file.filename or "file"
    ext = Path(name).suffix.lower()
    if ext not in (".exe", ".dll", ".cs"):
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_stream_"))
    target_path = tmp_dir / name

    try:
        contents = await file.read()
        target_path.write_bytes(contents)
    except Exception as e:
        raise HTTPException(500, f"Erro ao guardar ficheiro: {e}")

    output_dir = tmp_dir / "out"
    output_dir.mkdir(exist_ok=True)

    q: "queue.Queue[object]" = queue.Queue()

    def log_cb(msg: str) -> None:
        q.put({"type": "log", "message": msg})

    def worker():
        try:
            analyzer = RATAnalyzer(
                str(target_path),
                output_dir=str(output_dir),
                use_dotnet_decompiler=(ext in (".exe", ".dll")),
                log_callback=log_cb,
            )
            results = analyzer.analyze()

            last_path = output_dir / "last_analysis.json"
            report_content = ""
            c_code = ""
            il_code = ""
            flagged_indicators: list[str] = []
            flagged_functions: list[dict] = []

            if last_path.exists():
                with open(last_path, encoding="utf-8") as f:
                    last = json.load(f)
                report_path = last.get("report_path")

                def _read_file_safe_local(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
                    if not path or not Path(path).exists():
                        return ""
                    try:
                        with open(path, encoding=encoding, errors=errors) as fh:
                            return fh.read()
                    except Exception:
                        return ""

                report_content = _read_file_safe_local(report_path)
                flagged_indicators = last.get("flagged_indicators") or []
                flagged_functions = last.get("flagged_functions") or []

                deobf = last.get("deobfuscated_file")
                consolidated = last.get("consolidated_file")
                decompiled_c = last.get("decompiled_c_file")
                if deobf:
                    c_code = _read_file_safe_local(deobf)
                if not c_code and consolidated:
                    c_code = _read_file_safe_local(consolidated)
                if not c_code and decompiled_c:
                    c_code = _read_file_safe_local(decompiled_c)
                if not c_code and last.get("decompilation_error_summary"):
                    c_code = f"# Descompilação não disponível\n{last.get('decompilation_error_summary')}"
                # Aplicar resumo também no modo streaming
                c_code = summarize_c_code(c_code, flagged_indicators)

                disasm = last.get("disassembly_file")
                if disasm:
                    il_code = _read_file_safe_local(disasm, errors="replace")
                if not il_code:
                    il_code = "# Nenhum bytecode/assembly disponível para este ficheiro."
            else:
                report_content = "# Relatório não gerado."
                c_code = "# Código não disponível."
                il_code = "# Bytecode não disponível."

            payload = {
                "type": "result",
                "report": report_content,
                "cCode": c_code,
                "ilCode": il_code,
                "fileName": name,
                "riskScore": results.get("risk_score", 0),
                "riskLevel": results.get("risk_level", ""),
                "flaggedIndicators": flagged_indicators,
                # Funções suspeitas com ranges exatos no pseudo-C (quando existir pseudo-C da Ghidra).
                "flaggedFunctions": flagged_functions,
            }
            q.put(payload)
        except FileNotFoundError as e:
            q.put({"type": "error", "message": str(e)})
        except Exception as e:
            q.put({"type": "error", "message": f"Erro na análise: {e}"})
        finally:
            q.put(None)
            try:
                if target_path.exists():
                    target_path.unlink()
            except Exception:
                pass

    threading.Thread(target=worker, daemon=True).start()

    async def streamer():
        import anyio

        while True:
            item = await anyio.to_thread.run_sync(q.get)
            if item is None:
                break
            try:
                line = json.dumps(item, ensure_ascii=False) + "\n"
            except Exception:
                continue
            yield line.encode("utf-8")

    return StreamingResponse(streamer(), media_type="application/x-ndjson")


@app.post("/api/analysis")
async def submit_analysis(
    file: UploadFile = File(...),
    analysis_type: AnalysisType = Query(
        AnalysisType.STATIC,
        description="Tipo de análise: static, dynamic ou both.",
    ),
) -> dict:
    """
    Submete um job de análise (estática/dinâmica/ambas) e devolve um ID.

    Esta rota é a base da nova pipeline:
      - O ficheiro é guardado num diretório isolado em SANDBOX_JOBS_DIR
      - A análise estática reutiliza o RATAnalyzer existente
      - A análise dinâmica está ligada, por agora, a um stub onde o
        orquestrador de VMs será implementado.
    """
    name = file.filename or "file"
    ext = Path(name).suffix.lower()
    if ext not in (".exe", ".dll", ".cs"):
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    try:
        contents = await file.read()
    except Exception as e:  # noqa: BLE001
        raise HTTPException(500, f"Erro ao ler ficheiro: {e}")

    logger.info(
        "Pedido /api/analysis recebido: file=%s analysis_type=%s",
        name,
        analysis_type.value,
    )

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


@app.post("/api/analysis/upload_static")
async def upload_static_analysis(payload: StaticAnalysisUpload) -> dict:
    """Permite que um cliente (por exemplo, o WPF) publique um resultado de
    análise estática já concluído e receba um jobId compatível com
    /api/analysis/{jobId}.

    O frontend consegue depois consumir este job exatamente como qualquer
    outro criado via /api/analysis.
    """
    from analysis_jobs import AnalysisType, JobStatus  # import local para evitar ciclos
    import hashlib

    logger.info(
        "Pedido /api/analysis/upload_static recebido: file=%s score=%s level=%s",
        payload.fileName,
        payload.riskScore,
        payload.riskLevel,
    )

    job_id = str(uuid.uuid4())

    static_result = {
        "report": payload.report or "",
        "cCode": payload.cCode or "",
        "ilCode": payload.ilCode or "",
        "fileName": payload.fileName,
        "riskScore": int(payload.riskScore or 0),
        "riskLevel": payload.riskLevel or "",
        "flaggedIndicators": payload.flaggedIndicators or [],
        "flaggedFunctions": payload.flaggedFunctions or [],
    }

    # Como não temos acesso direto ao binário aqui, usamos um hash sintético
    # baseado nos campos principais apenas para fins de auditoria.
    h = hashlib.sha256()
    h.update((payload.fileName or "").encode("utf-8", "ignore"))
    h.update((payload.report or "").encode("utf-8", "ignore"))
    h.update((payload.cCode or "").encode("utf-8", "ignore"))
    h.update((payload.ilCode or "").encode("utf-8", "ignore"))
    sha = h.hexdigest()

    # Reutilizamos a pipeline de histórico existente: primeiro insert em estado queued,
    # depois update_results + update_status para completed.
    job_store.insert_job(
        job_id=job_id,
        analysis_type=AnalysisType.STATIC.value,
        file_name=payload.fileName,
        sha256=sha,
        status=JobStatus.QUEUED.value,
    )
    job_store.update_results(job_id, static_result, None)
    job_store.update_status(job_id, JobStatus.COMPLETED.value, error=None)

    logger.info(
        "Resultado estático publicado via /api/analysis/upload_static: job_id=%s file=%s",
        job_id,
        payload.fileName,
    )

    return {
        "jobId": job_id,
        "analysisType": AnalysisType.STATIC.value,
        "status": JobStatus.COMPLETED.value,
    }


def _get_job_output_dir(job_id: str) -> Path:
    """Diretório de saída do job (sandbox_jobs/{job_id}/out)."""
    return Path(config.SANDBOX_JOBS_DIR) / job_id / "out"


@app.get("/api/analysis/{job_id}/artifacts/obfuscated_snippets", response_class=PlainTextResponse)
async def get_obfuscated_snippets_artifact(
    job_id: str,
    variant: str = Query("obfuscated", description="obfuscated ou deobfuscated"),
) -> PlainTextResponse:
    """
    Devolve o conteúdo do ficheiro de trechos obfuscados ou deobfuscados do job.
    Valida que o path está dentro do output_dir do job (segurança).
    """
    import json
    out_dir = _get_job_output_dir(job_id)
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
        path_str = last.get("obfuscated_snippets_deobfuscated_file") or last.get("obfuscated_snippets_deobfuscated_pseudoc_file") or ""
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

    # Coerência com a categoria de risco "Obfuscation": se não há ficheiro de trechos mas há
    # indicadores de ofuscação (detetados no binário pelo Deobfuscator), devolver resumo.
    indicators = last.get("obfuscation_indicators") or []
    if not indicators and last.get("report_path"):
        try:
            out_dir_resolved = out_dir.resolve()
            report_path = Path(last["report_path"]).resolve()
            if report_path.exists() and (out_dir_resolved in report_path.parents or report_path.parent == out_dir_resolved):
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
        lines.append("Nota: Não foram extraídos trechos de código para este job (ex.: análise sem descompilação).")
        content = "\n".join(lines)
        return PlainTextResponse(content=content, media_type="text/plain; charset=utf-8")

    raise HTTPException(404, "Ficheiro de trechos não disponível para este job.")


@app.get("/api/analysis/{job_id}")
async def get_analysis_status(job_id: str) -> dict:
    """
    Devolve o estado e os resultados (quando disponíveis) de um job de análise.
    """
    logger.info("Pedido /api/analysis/%s recebido.", job_id)
    payload = get_job_payload(job_id)
    if not payload:
        logger.warning("Pedido /api/analysis/%s: job não encontrado.", job_id)
        raise HTTPException(404, "Job não encontrado.")

    logger.info(
        "Pedido /api/analysis/%s: devolvido status=%s analysisType=%s",
        job_id,
        payload.get("status"),
        payload.get("analysisType"),
    )
    return payload


@app.get("/api/analyses")
async def list_analyses(limit: int = 50, offset: int = 0) -> dict:
    """
    Lista histórico de análises (persistente em SQLite).
    """
    try:
        items = job_store.list_jobs(limit=limit, offset=offset)
        return {"items": items, "limit": limit, "offset": offset}
    except Exception as e:  # noqa: BLE001
        raise HTTPException(500, f"Erro ao listar análises: {e}")


@app.get("/api/health")
async def health():
    return {"status": "ok"}
