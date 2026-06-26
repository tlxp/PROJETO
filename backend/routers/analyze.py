# --- Módulo: analyze ---
# Endpoints de análise estática síncrona e streaming.

from __future__ import annotations

import json
import logging
import queue
import shutil
import tempfile
import threading
import time
from pathlib import Path

import anyio.to_thread
from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse

from c_code_payload import (
    compose_fallback_descompilation_ccode,
    should_compose_decompilation_fallback,
    summarize_c_code_payload,
)
from observability import increment
from i18n import current_lang, resolve_lang, t
from rat_analyzer import RATAnalyzer
from upload_security import get_max_upload_bytes, resolve_safe_path

from .deps import (
    ALLOWED_UPLOAD_EXTENSIONS,
    check_content_length,
    read_file_safe,
    require_api_token,
    sanitize_upload_name,
    stream_upload_to_path,
)

logger = logging.getLogger("rat_analyzer_api")

router = APIRouter(tags=["analyze"])


# --- Análise estática síncrona (upload + RATAnalyzer) ---
@router.post("/api/analyze", dependencies=[Depends(require_api_token)])
async def analyze_file(request: Request, file: UploadFile = File(...)):
    increment("rat_analyzer_analyze_requests_total")
    client_host = request.client.host if request.client else "unknown"
    name = sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        logger.warning("Rejeitado ficheiro %s (%s) de %s: extensão não suportada", name, ext, client_host)
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    check_content_length(request, max_bytes)

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_"))
    try:
        target_path = resolve_safe_path(tmp_dir, name)
    except ValueError:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(400, "Nome de ficheiro inválido.")

    logger.info("Recebido pedido /api/analyze de %s para ficheiro %s (ext=%s)", client_host, name, ext)
    try:
        try:
            await stream_upload_to_path(file, target_path, max_bytes)
        except HTTPException:
            raise
        except Exception:
            logger.exception("Erro ao guardar upload de %s em %s", name, target_path)
            raise HTTPException(500, "Erro ao guardar o ficheiro enviado.")

        start_time = time.perf_counter()
        try:
            output_dir = tmp_dir / "out"
            output_dir.mkdir(exist_ok=True)

# --- Callback de log do pipeline ---
            def log_cb(msg: str) -> None:
                logger.info("[ANALYZE %s] %s", name, msg)

            analyzer = RATAnalyzer(
                str(target_path),
                output_dir=str(output_dir),
                use_dotnet_decompiler=(ext in (".exe", ".dll")),
                log_callback=log_cb,
            )
            logger.info("Iniciar análise estática para %s", target_path)
            results = await anyio.to_thread.run_sync(analyzer.analyze)
            elapsed = time.perf_counter() - start_time
            logger.info(
                "Análise terminada para %s em %.1f segundos (risk_score=%s, risk_level=%s)",
                name,
                elapsed,
                results.get("risk_score"),
                results.get("risk_level"),
            )
        except FileNotFoundError:
            logger.exception("Erro FileNotFound durante análise de %s", name)
            raise HTTPException(400, "Ficheiro não encontrado durante a análise.")
        except Exception:
            logger.exception("Erro inesperado durante análise de %s", name)
            raise HTTPException(500, "Erro interno na análise.")

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
            report_content = read_file_safe(report_path)
            flagged_indicators = last.get("flagged_indicators") or []
            flagged_functions = last.get("flagged_functions") or []

            deobf = last.get("deobfuscated_file")
            consolidated = last.get("consolidated_file")
            decompiled_c = last.get("decompiled_c_file")
            if deobf:
                c_code = read_file_safe(deobf)
            if not c_code and consolidated:
                c_code = read_file_safe(consolidated)
            if not c_code and decompiled_c:
                c_code = read_file_safe(decompiled_c)
            if not c_code and should_compose_decompilation_fallback(last):
                c_code = compose_fallback_descompilation_ccode(last)
            c_code, flagged_functions = summarize_c_code_payload(c_code, flagged_indicators, flagged_functions)

            disasm = last.get("disassembly_file")
            if disasm:
                il_code = read_file_safe(disasm, errors="replace")
            if not il_code:
                il_code = t("no_bytecode", current_lang())
        else:
            report_content = t("report_not_generated", current_lang())
            c_code = t("code_not_available", current_lang())
            il_code = t("bytecode_not_available", current_lang())

        return {
            "report": report_content,
            "cCode": c_code,
            "ilCode": il_code,
            "fileName": name,
            "riskScore": results.get("risk_score", 0),
            "riskLevel": results.get("risk_level", ""),
            "flaggedIndicators": flagged_indicators,
            "flaggedFunctions": flagged_functions,
        }
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


# --- Análise estática com streaming NDJSON de logs e resultado ---
@router.post("/api/analyze_stream", dependencies=[Depends(require_api_token)])
async def analyze_file_stream(request: Request, file: UploadFile = File(...)):
    increment("rat_analyzer_analyze_stream_requests_total")
    name = sanitize_upload_name(file.filename)
    ext = Path(name).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    max_bytes = get_max_upload_bytes()
    check_content_length(request, max_bytes)

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_stream_"))
    try:
        target_path = resolve_safe_path(tmp_dir, name)
    except ValueError:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(400, "Nome de ficheiro inválido.")

    try:
        await stream_upload_to_path(file, target_path, max_bytes)
    except HTTPException:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise
    except Exception:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        logger.exception("Erro ao guardar upload de %s em %s", name, target_path)
        raise HTTPException(500, "Erro ao guardar o ficheiro enviado.")

    output_dir = tmp_dir / "out"
    output_dir.mkdir(exist_ok=True)
    q: queue.Queue[object] = queue.Queue()

# --- Callback de log para streaming SSE ---
    def log_cb(msg: str) -> None:
        q.put({"type": "log", "message": msg})

    # --- Worker em thread separada para análise e envio de eventos ---
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

# --- Leitura segura de ficheiro local para resposta ---
                def _read_local(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
                    if not path or not Path(path).exists():
                        return ""
                    try:
                        with open(path, encoding=encoding, errors=errors) as fh:
                            return fh.read()
                    except Exception:
                        return ""

                report_content = _read_local(report_path)
                flagged_indicators = last.get("flagged_indicators") or []
                flagged_functions = last.get("flagged_functions") or []

                deobf = last.get("deobfuscated_file")
                consolidated = last.get("consolidated_file")
                decompiled_c = last.get("decompiled_c_file")
                if deobf:
                    c_code = _read_local(deobf)
                if not c_code and consolidated:
                    c_code = _read_local(consolidated)
                if not c_code and decompiled_c:
                    c_code = _read_local(decompiled_c)
                if not c_code and should_compose_decompilation_fallback(last):
                    c_code = compose_fallback_descompilation_ccode(last)
                c_code, flagged_functions = summarize_c_code_payload(
                    c_code, flagged_indicators, flagged_functions
                )

                disasm = last.get("disassembly_file")
                if disasm:
                    il_code = _read_local(disasm, errors="replace")
                if not il_code:
                    il_code = t("no_bytecode", current_lang())
            else:
                report_content = t("report_not_generated", current_lang())
                c_code = t("code_not_available", current_lang())
                il_code = t("bytecode_not_available", current_lang())

            q.put(
                {
                    "type": "result",
                    "report": report_content,
                    "cCode": c_code,
                    "ilCode": il_code,
                    "fileName": name,
                    "riskScore": results.get("risk_score", 0),
                    "riskLevel": results.get("risk_level", ""),
                    "flaggedIndicators": flagged_indicators,
                    "flaggedFunctions": flagged_functions,
                }
            )
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

    # --- Gerador async que consome a fila e emite NDJSON ---
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
