"""Dependências e helpers partilhados pelos routers."""

from __future__ import annotations

import logging
import os
import secrets
from pathlib import Path

from fastapi import Header, HTTPException, Request, UploadFile

import config
from security_config import api_token_configured, require_api_token_enforced
from storage_maintenance import read_text_artifact_from_job
from upload_security import (
    UPLOAD_CHUNK_SIZE,
    get_max_upload_bytes,
    is_valid_job_id,
    resolve_safe_path,
    sanitize_upload_filename,
)

logger = logging.getLogger("rat_analyzer_api")

ALLOWED_UPLOAD_EXTENSIONS = (".exe", ".dll", ".cs")


def require_api_token(
    x_api_token: str | None = Header(default=None, alias="X-API-Token"),
) -> None:
    """Valida X-API-Token quando RATANALYZER_API_TOKEN está definido."""
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


def require_valid_job_id(job_id: str) -> str:
    if not is_valid_job_id(job_id):
        raise HTTPException(400, "job_id inválido (esperado UUID v4).")
    return job_id


def get_job_output_dir(job_id: str) -> Path:
    require_valid_job_id(job_id)
    return Path(config.SANDBOX_JOBS_DIR) / job_id / "out"


def sanitize_upload_name(raw_name: str | None) -> str:
    try:
        return sanitize_upload_filename(raw_name)
    except ValueError as e:
        logger.warning("Upload rejeitado: filename inseguro (%r): %s", raw_name, e)
        raise HTTPException(400, "Nome de ficheiro inválido.")


def check_content_length(request: Request, max_bytes: int) -> None:
    raw = request.headers.get("content-length")
    if not raw:
        return
    try:
        declared = int(raw)
    except ValueError:
        return
    if declared > max_bytes + UPLOAD_CHUNK_SIZE:
        raise HTTPException(413, f"Ficheiro excede o limite de upload ({max_bytes // (1024 * 1024)} MB).")


async def stream_upload_to_path(file: UploadFile, target_path: Path, max_bytes: int) -> int:
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


async def read_upload_bytes(file: UploadFile, max_bytes: int) -> bytes:
    buf = bytearray()
    while True:
        chunk = await file.read(UPLOAD_CHUNK_SIZE)
        if not chunk:
            break
        buf.extend(chunk)
        if len(buf) > max_bytes:
            raise HTTPException(413, f"Ficheiro excede o limite de upload ({max_bytes // (1024 * 1024)} MB).")
    return bytes(buf)


def read_file_safe(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
    if not path:
        return ""
    p = Path(path)
    if not p.exists():
        try:
            base = Path(config.SANDBOX_JOBS_DIR).resolve()
            rp = p.resolve()
            if base in rp.parents:
                parts = list(rp.parts)
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


def summarize_dynamic_report(report: str) -> str:
    if not report or not report.strip():
        return "Análise dinâmica na VM concluída."
    for line in report.splitlines():
        trimmed = line.strip()
        if trimmed and not trimmed.startswith("=") and not trimmed.startswith("-"):
            return trimmed[:240]
    return "Análise dinâmica na VM concluída."
