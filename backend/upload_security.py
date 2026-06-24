# --- Módulo: upload_security ---
# Helpers de segurança para uploads e identificadores de jobs:
# sanitização de nomes, validação UUID v4 e limite de tamanho.

from __future__ import annotations

import os
import re
from pathlib import Path, PureWindowsPath, PurePosixPath

# *Regex UUID v4 (aceita maiúsculas/minúsculas)*
_UUID4_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)

DEFAULT_MAX_UPLOAD_MB = 100

# *Tamanho de chunk para leitura de uploads (1 MiB)*
UPLOAD_CHUNK_SIZE = 1024 * 1024


# --- Validação de job_id como UUID v4 ---
def is_valid_job_id(job_id: str) -> bool:
    if not job_id or not isinstance(job_id, str):
        return False
    return bool(_UUID4_RE.match(job_id))


# --- Sanitização do nome de ficheiro recebido num upload ---
def sanitize_upload_filename(raw_name: str | None) -> str:
    name = (raw_name or "").strip()
    if not name:
        raise ValueError("Nome de ficheiro vazio.")

    # *Rejeitar separadores e paths absolutos em qualquer convenção*
    if "/" in name or "\\" in name:
        raise ValueError("Nome de ficheiro não pode conter separadores de path.")
    if PureWindowsPath(name).is_absolute() or PurePosixPath(name).is_absolute():
        raise ValueError("Nome de ficheiro não pode ser um path absoluto.")
    if re.match(r"^[A-Za-z]:", name):
        raise ValueError("Nome de ficheiro não pode conter letra de unidade.")

    safe = Path(name).name
    if not safe or safe in (".", ".."):
        raise ValueError("Nome de ficheiro inválido.")
    if safe != name:
        raise ValueError("Nome de ficheiro inválido após normalização.")
    if any(ord(c) < 32 for c in safe):
        raise ValueError("Nome de ficheiro contém caracteres de controlo.")
    return safe


# --- Resolução segura de path dentro do diretório base ---
def resolve_safe_path(base_dir: Path, file_name: str) -> Path:
    base_resolved = Path(base_dir).resolve()
    target = (base_resolved / file_name).resolve()
    if not target.is_relative_to(base_resolved):
        raise ValueError("Path resultante fora do diretório base.")
    return target


# --- Limite de upload em bytes (env RATANALYZER_MAX_UPLOAD_MB) ---
def get_max_upload_bytes() -> int:
    raw = (os.environ.get("RATANALYZER_MAX_UPLOAD_MB") or "").strip()
    try:
        mb = int(raw) if raw else DEFAULT_MAX_UPLOAD_MB
    except ValueError:
        mb = DEFAULT_MAX_UPLOAD_MB
    if mb <= 0:
        mb = DEFAULT_MAX_UPLOAD_MB
    return mb * 1024 * 1024
