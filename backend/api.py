"""
API REST para o RAT Analyzer.
Expõe um endpoint de upload e análise para o frontend (drop-n-analyze) e para o WPF.
"""

import os
import secrets
import sys
import uuid
import tempfile
import shutil
import time
import logging
from contextlib import asynccontextmanager
from pathlib import Path
import anyio.to_thread
from fastapi import Depends, FastAPI, File, Header, UploadFile, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from pydantic import BaseModel

# Garantir que o projeto está no path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT_ROOT))

import config
from security_config import api_token_configured, require_api_token_enforced, validate_startup_secrets
from artifact_naming import short_stem, short_filename
from rat_analyzer import RATAnalyzer
from analysis_jobs import (
    AnalysisType,
    AnalysisJob,
    compose_fallback_descompilation_ccode,
    create_job,
    get_job,
    get_job_payload,
    should_compose_decompilation_fallback,
    summarize_c_code_payload,
)
from modules.pseudo_c_highlighter import realign_flagged_functions_for_payload
import job_store
from storage_maintenance import estimate_storage, cleanup_job_artifacts, archive_cold_jobs, purge_all_storage, read_text_artifact_from_job
from upload_security import (
    UPLOAD_CHUNK_SIZE,
    get_max_upload_bytes,
    is_valid_job_id,
    resolve_safe_path,
    sanitize_upload_filename,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("rat_analyzer_api")

ALLOWED_UPLOAD_EXTENSIONS = (".exe", ".dll", ".cs")


@asynccontextmanager
async def _lifespan(app: FastAPI):
    validate_startup_secrets()

    # Garantir DB/migrações e diretórios de data.
    try:
        job_store.init_db()
        Path(config.REPORTS_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.DECOMPILED_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.SANDBOX_JOBS_DIR).mkdir(parents=True, exist_ok=True)
    except Exception:
        logger.exception("Falha no startup ao inicializar diretórios/DB.")

    # Retenção/arquivo "soft": falhas nunca devem impedir o servidor de arrancar.
    try:
        cleanup_job_artifacts(config.JOBS_RETENTION_DAYS, config.JOBS_MAX_COUNT)
    except Exception:
        logger.exception("Falha na limpeza de artefactos no startup (continua o arranque).")
    try:
        archive_cold_jobs(config.COLD_ARCHIVE_DAYS)
    except Exception:
        logger.exception("Falha no arquivo frio de jobs no startup (continua o arranque).")

    yield


app = FastAPI(title="RAT Analyzer API v2", version="1.0.0", lifespan=_lifespan)


def _cors_origins() -> list[str]:
    """Origens CORS via env RATANALYZER_CORS_ORIGINS (lista separada por vírgulas)."""
    raw = (os.environ.get("RATANALYZER_CORS_ORIGINS") or "").strip()
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]
    return [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
    ]


# CORS para o frontend React (Vite normalmente em localhost:8080 ou 5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(),
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Accept", "X-API-Token"],
)


def require_api_token(
    x_api_token: str | None = Header(default=None, alias="X-API-Token"),
) -> None:
    """
    Proteção opcional de endpoints que aceitam uploads ou alteram estado.

    Se RATANALYZER_API_TOKEN estiver definido, o header X-API-Token tem de
    coincidir (comparação em tempo constante). Sem a env definida, o
    comportamento actual mantém-se (sem autenticação — apenas dev local).
    """
    token = (os.environ.get("RATANALYZER_API_TOKEN") or "").strip()
    if not token:
        if require_api_token_enforced():
            raise HTTPException(
                503,
                "Token de API obrigatório mas RATANALYZER_API_TOKEN não está configurado.",
            )
        return
    provided = (x_api_token or "").strip()
    if not provided or not secrets.compare_digest(provided.encode("utf-8"), token.encode("utf-8")):
        raise HTTPException(401, "Token de API inválido ou em falta (header X-API-Token).")


def _require_valid_job_id(job_id: str) -> str:
    """Valida job_id como UUID v4; devolve 400 se inválido."""
    if not is_valid_job_id(job_id):
        raise HTTPException(400, "job_id inválido (esperado UUID v4).")
    return job_id


def _sanitize_upload_name(raw_name: str | None) -> str:
    """Sanitiza o filename de um upload; devolve 400 se for inseguro/ inválido."""
    try:
        return sanitize_upload_filename(raw_name)
    except ValueError as e:
        logger.warning("Upload rejeitado: filename inseguro (%r): %s", raw_name, e)
        raise HTTPException(400, "Nome de ficheiro inválido.")


def _check_content_length(request: Request, max_bytes: int) -> None:
    """Rejeita cedo pedidos cujo Content-Length excede o limite (quando presente)."""
    raw = request.headers.get("content-length")
    if not raw:
        return
    try:
        declared = int(raw)
    except ValueError:
        return
    # Margem para overhead do multipart (boundaries/headers)
    if declared > max_bytes + UPLOAD_CHUNK_SIZE:
        raise HTTPException(413, f"Ficheiro excede o limite de upload ({max_bytes // (1024 * 1024)} MB).")


async def _stream_upload_to_path(file: UploadFile, target_path: Path, max_bytes: int) -> int:
    """Escreve o upload em disco por chunks; devolve 413 se exceder o limite."""
    total = 0
    try:
        with open(target_path, "wb") as out:
            while True:
                chunk = await file.read(UPLOAD_CHUNK_SIZE)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise HTTPException(413, f"Ficheiro excede o limite de upload ({max_bytes // (1024 * 1024)} MB).")
                out.write(chunk)
    except HTTPException:
        try:
            target_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    return total


async def _read_upload_bytes(file: UploadFile, max_bytes: int) -> bytes:
    """Lê o upload por chunks com limite de tamanho; devolve 413 se exceder."""
    buf = bytearray()
    while True:
        chunk = await file.read(UPLOAD_CHUNK_SIZE)
        if not chunk:
            break
        buf.extend(chunk)
        if len(buf) > max_bytes:
            raise HTTPException(413, f"Ficheiro excede o limite de upload ({max_bytes // (1024 * 1024)} MB).")
    return bytes(buf)

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
        # Transparência: se o path aponta para um artefacto dentro de sandbox_jobs/<job_id>/out/
        # mas out/ foi arquivado em out.zip, tentar ler do zip.
        try:
            base = Path(config.SANDBOX_JOBS_DIR).resolve()
            rp = p.resolve()
            if base in rp.parents:
                # procurar ".../sandbox_jobs/<job_id>/out/<rel>"
                parts = list(rp.parts)
                # encontrar index de sandbox_jobs e job_id
                if "sandbox_jobs" in parts:
                    i = parts.index("sandbox_jobs")
                    if i + 2 < len(parts) and parts[i + 2] == "out":
                        job_id = parts[i + 1]
                        rel = str(Path(*parts[i + 3 :])).replace("\\", "/")
                        txt = read_text_artifact_from_job(job_id, rel)
                        return txt or ""
        except Exception:
            pass
        return ""
    try:
        with open(p, encoding=encoding, errors=errors) as f:
            return f.read()
    except Exception:  # noqa: BLE001
        return ""


@app.post("/api/analyze", dependencies=[Depends(require_api_token)])
async def analyze_file(request: Request, file: UploadFile = File(...)):
    """
    Recebe um ficheiro (.exe, .dll, .cs), executa a análise e devolve
    relatório, código C#/C e assembly/IL para exibir no frontend.
    """
    client_host = request.client.host if request.client else "unknown"
    # Sanitizar nome e validar extensão
    name = _sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        logger.warning("Rejeitado ficheiro %s (%s) de %s: extensão não suportada", name, ext, client_host)
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    _check_content_length(request, max_bytes)

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_"))
    try:
        target_path = resolve_safe_path(tmp_dir, name)
    except ValueError:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(400, "Nome de ficheiro inválido.")

    logger.info("Recebido pedido /api/analyze de %s para ficheiro %s (ext=%s)", client_host, name, ext)
    try:
        try:
            await _stream_upload_to_path(file, target_path, max_bytes)
        except HTTPException:
            raise
        except Exception:
            logger.exception("Erro ao guardar upload de %s em %s", name, target_path)
            raise HTTPException(500, "Erro ao guardar o ficheiro enviado.")

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
            # Correr a análise (pesada e síncrona) fora do event loop
            results = await anyio.to_thread.run_sync(analyzer.analyze)
            elapsed = time.perf_counter() - start_time
            logger.info("Análise terminada para %s em %.1f segundos (risk_score=%s, risk_level=%s)",
                        name, elapsed, results.get("risk_score"), results.get("risk_level"))
        except FileNotFoundError:
            logger.exception("Erro FileNotFound durante análise de %s", name)
            raise HTTPException(400, "Ficheiro não encontrado durante a análise.")
        except Exception:
            logger.exception("Erro inesperado durante análise de %s", name)
            raise HTTPException(500, "Erro interno na análise.")

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
            if not c_code and should_compose_decompilation_fallback(last):
                c_code = compose_fallback_descompilation_ccode(last)
            # Aplicar resumo para evitar payloads gigantes no frontend
            c_code, flagged_functions = summarize_c_code_payload(
                c_code, flagged_indicators, flagged_functions
            )

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
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


@app.post("/api/analyze_stream", dependencies=[Depends(require_api_token)])
async def analyze_file_stream(request: Request, file: UploadFile = File(...)):
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

    name = _sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    _check_content_length(request, max_bytes)

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_stream_"))
    try:
        target_path = resolve_safe_path(tmp_dir, name)
    except ValueError:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(400, "Nome de ficheiro inválido.")

    try:
        await _stream_upload_to_path(file, target_path, max_bytes)
    except HTTPException:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise
    except Exception:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        logger.exception("Erro ao guardar upload de %s em %s", name, target_path)
        raise HTTPException(500, "Erro ao guardar o ficheiro enviado.")

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
                if not c_code and should_compose_decompilation_fallback(last):
                    c_code = compose_fallback_descompilation_ccode(last)
                # Aplicar resumo também no modo streaming
                c_code, flagged_functions = summarize_c_code_payload(
                    c_code, flagged_indicators, flagged_functions
                )

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
        except FileNotFoundError:
            logger.exception("Ficheiro não encontrado durante análise (stream) de %s", name)
            q.put({"type": "error", "message": "Ficheiro não encontrado durante a análise."})
        except Exception:
            logger.exception("Erro inesperado durante análise (stream) de %s", name)
            q.put({"type": "error", "message": "Erro interno na análise."})
        finally:
            q.put(None)
            shutil.rmtree(tmp_dir, ignore_errors=True)

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


@app.post("/api/analysis", dependencies=[Depends(require_api_token)])
async def submit_analysis(
    request: Request,
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
    name = _sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    _check_content_length(request, max_bytes)

    try:
        contents = await _read_upload_bytes(file, max_bytes)
    except HTTPException:
        raise
    except Exception:  # noqa: BLE001
        logger.exception("Erro ao ler upload de %s", name)
        raise HTTPException(500, "Erro ao ler o ficheiro enviado.")

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


@app.post("/api/analysis/upload_static", dependencies=[Depends(require_api_token)])
async def upload_static_analysis(payload: StaticAnalysisUpload) -> dict:
    """Permite que um cliente (por exemplo, o WPF) publique um resultado de
    análise estática já concluído e receba um jobId compatível com
    /api/analysis/{jobId}.

    O frontend consegue depois consumir este job exatamente como qualquer
    outro criado via /api/analysis.
    """
    from analysis_jobs import AnalysisType, JobStatus  # import local para evitar ciclos
    from modules.deobfuscator import Deobfuscator
    from modules.obfuscation_snippet_extractor import extract_and_write_snippets_from_content
    import hashlib
    import json

    logger.info(
        "Pedido /api/analysis/upload_static recebido: file=%s score=%s level=%s",
        payload.fileName,
        payload.riskScore,
        payload.riskLevel,
    )

    job_id = str(uuid.uuid4())

    out_dir = _get_job_output_dir(job_id)
    out_dir.mkdir(parents=True, exist_ok=True)

    base_name = short_stem(Path(payload.fileName or "analysis").stem or "analysis")
    report_path = out_dir / short_filename(base_name, "report", ext="txt")
    c_code_path = out_dir / short_filename(base_name, "c", ext="txt")
    il_code_path = out_dir / short_filename(base_name, "il", ext="txt")

    try:
        report_path.write_text(payload.report or "", encoding="utf-8", errors="replace")
    except OSError:
        logger.warning("Falha ao guardar report.txt para job_id=%s", job_id)
    try:
        c_code_path.write_text(payload.cCode or "", encoding="utf-8", errors="replace")
    except OSError:
        logger.warning("Falha ao guardar cCode para job_id=%s", job_id)
    try:
        il_code_path.write_text(payload.ilCode or "", encoding="utf-8", errors="replace")
    except OSError:
        logger.warning("Falha ao guardar ilCode para job_id=%s", job_id)

    obf_snippets = ""
    obf_snippets_deob = ""
    obf_summary: dict[str, int] = {}
    if payload.cCode and payload.cCode.strip():
        try:
            deob = Deobfuscator()
            obf_snippets, obf_snippets_deob, obf_summary = extract_and_write_snippets_from_content(
                content=payload.cCode,
                source_path=str(c_code_path),
                output_dir=out_dir,
                stem=base_name,
                deobfuscate_fn=deob.deobfuscate_content,
            )
        except Exception:
            logger.exception("Falha ao extrair snippets de ofuscação em upload_static (job_id=%s).", job_id)

    obfuscation_indicator_count = int(sum(obf_summary.values())) if obf_summary else 0

    c_code = payload.cCode or ""
    flagged_functions = realign_flagged_functions_for_payload(
        c_code, payload.flaggedFunctions or []
    )

    static_result = {
        "report": payload.report or "",
        "cCode": c_code,
        "ilCode": payload.ilCode or "",
        "fileName": payload.fileName,
        "riskScore": int(payload.riskScore or 0),
        "riskLevel": payload.riskLevel or "",
        "flaggedIndicators": payload.flaggedIndicators or [],
        "flaggedFunctions": flagged_functions,
        "obfuscatedSnippetsFile": obf_snippets,
        "obfuscatedSnippetsDeobfuscatedFile": obf_snippets_deob,
        "obfuscationIndicatorCount": obfuscation_indicator_count,
    }

    last_analysis_payload = {
        "target_file": payload.fileName or "",
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
        # Mantemos vazio para permitir fallback por parsing de relatório
        # quando não existirem snippets.
        "obfuscation_indicators": [],
    }
    try:
        last_path = out_dir / "last_analysis.json"
        last_path.write_text(
            json.dumps(last_analysis_payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
            errors="replace",
        )
    except OSError:
        logger.warning("Falha ao guardar last_analysis.json para job_id=%s", job_id)

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
    """Diretório de saída do job (sandbox_jobs/{job_id}/out). Valida o job_id."""
    _require_valid_job_id(job_id)
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
    _require_valid_job_id(job_id)
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

    # Fallback inteligente:
    # Se não houver ficheiro de snippets em disco, tentar reconstruí-los on-demand
    # a partir do cCode armazenado no payload do job (memória/DB).
    try:
        payload = get_job_payload(job_id) or {}
        static_result = payload.get("staticResult") if isinstance(payload, dict) else {}
        if isinstance(static_result, dict):
            c_code = static_result.get("cCode") or ""
            file_name = static_result.get("fileName") or "analysis"
            if isinstance(c_code, str) and c_code.strip():
                from modules.deobfuscator import Deobfuscator
                from modules.obfuscation_snippet_extractor import extract_and_write_snippets_from_content

                stem = Path(str(file_name)).stem or "analysis"
                stem = short_stem(stem)
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
    _require_valid_job_id(job_id)
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
    limit = min(max(1, limit), 200)
    offset = max(0, offset)
    try:
        items = job_store.list_jobs(limit=limit, offset=offset)
        return {"items": items, "limit": limit, "offset": offset}
    except Exception:  # noqa: BLE001
        logger.exception("Erro ao listar análises (limit=%s, offset=%s)", limit, offset)
        raise HTTPException(500, "Erro ao listar análises.")


@app.get("/api/health")
async def health():
    return {"status": "ok"}


@app.get("/api/storage/estimate")
async def storage_estimate() -> dict:
    """Estimativa de espaço por categoria (para UI de manutenção)."""
    est = estimate_storage(project_root=config.PROJECT_ROOT)
    return {
        "paths": {
            "dataDir": str(getattr(config, "DATA_DIR", "")),
            "sandboxJobsDir": str(config.SANDBOX_JOBS_DIR),
            "reportsDir": str(config.REPORTS_DIR),
            "decompiledDir": str(config.DECOMPILED_DIR),
        },
        "bytes": {
            "sandboxJobs": est.sandbox_jobs_bytes,
            "reports": est.reports_bytes,
            "decompiled": est.decompiled_bytes,
            "pythonCache": est.python_cache_bytes,
            "wpfBuild": est.wpf_build_bytes,
            "frontendDist": est.frontend_dist_bytes,
            "total": est.total_bytes,
        },
    }


class StorageCleanupRequest(BaseModel):
    retentionDays: int = 30
    keepMostRecent: int = 200


@app.post("/api/storage/cleanup", dependencies=[Depends(require_api_token)])
async def storage_cleanup(req: StorageCleanupRequest) -> dict:
    """
    Limpeza segura (soft) de artefactos antigos: remove apenas conteúdo de disco
    em sandbox_jobs/<job_id> para jobs COMPLETED/FAILED, mantendo DB.
    """
    result = cleanup_job_artifacts(req.retentionDays, req.keepMostRecent)
    return {"ok": True, "result": result}


class StorageArchiveRequest(BaseModel):
    olderThanDays: int = 30


@app.post("/api/storage/archive", dependencies=[Depends(require_api_token)])
async def storage_archive(req: StorageArchiveRequest) -> dict:
    """Arquivo frio: zip de out/ e remoção do diretório original."""
    result = archive_cold_jobs(req.olderThanDays)
    return {"ok": True, "result": result}


@app.post("/api/storage/purge", dependencies=[Depends(require_api_token)])
async def storage_purge() -> dict:
    """Limpeza completa: apaga todo o histórico e artefactos persistidos em DATA_DIR.

    Bloqueado (409) enquanto existirem jobs em execução, para não apagar
    diretórios/DB em uso pela pipeline.
    """
    try:
        running = job_store.count_jobs_by_status("running")
    except Exception:
        logger.exception("Falha ao verificar jobs em execução antes do purge.")
        running = 0
    if running > 0:
        raise HTTPException(409, f"Existem {running} job(s) em execução. Aguarde a conclusão antes de purgar.")
    result = purge_all_storage()
    return {"ok": True, "result": result}
