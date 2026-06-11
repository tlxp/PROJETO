"""
Helpers de segurança para uploads e identificadores de jobs.

- Sanitização de nomes de ficheiro enviados por clientes (path traversal).
- Validação de job_id como UUID v4.
- Limite de tamanho de upload configurável (RATANALYZER_MAX_UPLOAD_MB).
"""

from __future__ import annotations

import os
import re
from pathlib import Path, PureWindowsPath, PurePosixPath

# UUID v4 (aceita maiúsculas/minúsculas)
_UUID4_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)

DEFAULT_MAX_UPLOAD_MB = 100

# Tamanho de chunk para leitura de uploads (1 MiB)
UPLOAD_CHUNK_SIZE = 1024 * 1024


def is_valid_job_id(job_id: str) -> bool:
    """Valida que o job_id é um UUID v4."""
    if not job_id or not isinstance(job_id, str):
        return False
    return bool(_UUID4_RE.match(job_id))


def sanitize_upload_filename(raw_name: str | None) -> str:
    """
    Sanitiza o nome de ficheiro recebido num upload.

    Regras:
      - rejeita nomes vazios;
      - rejeita separadores de path ('/', '\\') e paths absolutos (ex.: 'C:\\x.exe');
      - rejeita componentes '..' / '.';
      - devolve apenas o nome base (Path(name).name).

    Levanta ValueError se o nome for inseguro.
    """
    name = (raw_name or "").strip()
    if not name:
        raise ValueError("Nome de ficheiro vazio.")

    # Rejeitar separadores e paths absolutos em qualquer convenção (Windows/Posix)
    if "/" in name or "\\" in name:
        raise ValueError("Nome de ficheiro não pode conter separadores de path.")
    if PureWindowsPath(name).is_absolute() or PurePosixPath(name).is_absolute():
        raise ValueError("Nome de ficheiro não pode ser um path absoluto.")
    # Drive letter (ex.: 'C:x.exe') sem separador também é suspeito
    if re.match(r"^[A-Za-z]:", name):
        raise ValueError("Nome de ficheiro não pode conter letra de unidade.")

    safe = Path(name).name
    if not safe or safe in (".", ".."):
        raise ValueError("Nome de ficheiro inválido.")
    if safe != name:
        raise ValueError("Nome de ficheiro inválido após normalização.")
    # Caracteres de controlo
    if any(ord(c) < 32 for c in safe):
        raise ValueError("Nome de ficheiro contém caracteres de controlo.")
    return safe


def resolve_safe_path(base_dir: Path, file_name: str) -> Path:
    """
    Junta base_dir + file_name (já sanitizado) e garante que o resultado
    permanece dentro de base_dir. Levanta ValueError caso contrário.
    """
    base_resolved = Path(base_dir).resolve()
    target = (base_resolved / file_name).resolve()
    if not target.is_relative_to(base_resolved):
        raise ValueError("Path resultante fora do diretório base.")
    return target


def get_max_upload_bytes() -> int:
    """Limite de upload em bytes (env RATANALYZER_MAX_UPLOAD_MB, default 100)."""
    raw = (os.environ.get("RATANALYZER_MAX_UPLOAD_MB") or "").strip()
    try:
        mb = int(raw) if raw else DEFAULT_MAX_UPLOAD_MB
    except ValueError:
        mb = DEFAULT_MAX_UPLOAD_MB
    if mb <= 0:
        mb = DEFAULT_MAX_UPLOAD_MB
    return mb * 1024 * 1024
