# --- Módulo: artifact_naming ---
# Naming curto e seguro para artefatos/pastas: slug + hash curto (estável)
# para evitar colisões e respeitar limites do Windows.

from __future__ import annotations

import hashlib
import re
import unicodedata


_SAFE_RE = re.compile(r"[^A-Za-z0-9._-]+")


# --- Hash SHA-1 truncado a 8 caracteres ---
def _hash8(text: str) -> str:
    h = hashlib.sha1((text or "").encode("utf-8", "ignore")).hexdigest()
    return h[:8]


# --- Conversão de texto em slug seguro para ficheiros ---
def slugify(text: str, max_len: int = 32) -> str:
    raw = (text or "").strip()
    if not raw:
        return "x"
    # *Normalizar Unicode e remover acentos*
    norm = unicodedata.normalize("NFKD", raw)
    norm = "".join(ch for ch in norm if not unicodedata.combining(ch))
    norm = _SAFE_RE.sub("_", norm)
    norm = re.sub(r"_+", "_", norm).strip("_")
    out = norm or "x"
    # *Segmentos que começam por '.' falham em algumas APIs Java (Ghidra/JDK)*
    out = out.lstrip(".") or "x"
    return out[:max_len] if len(out) > max_len else out


# --- Stem curto com sufixo de hash estável ---
def short_stem(stem: str, max_slug: int = 40) -> str:
    s = (stem or "").strip() or "output"
    slug = slugify(s, max_len=max_slug)
    h = _hash8(s)
    return f"{slug}-{h}"


# --- Nome de ficheiro curto a partir de partes e extensão ---
def short_filename(*parts: str, ext: str, max_total: int = 140) -> str:
    ext = ext if ext.startswith(".") else f".{ext}"
    raw_parts = [p for p in parts if (p or "").strip()]
    key = "|".join(raw_parts) or "x"
    h = _hash8(key)
    compact = [slugify(p, 28) for p in raw_parts[:4]]
    name = ".".join([*compact, h]) + ext
    if len(name) <= max_total:
        return name
    # *Fallback mais curto se exceder limite total*
    base = slugify(raw_parts[0] if raw_parts else "x", 28)
    name = ".".join([base, h]) + ext
    if len(name) <= max_total:
        return name
    return f"h{h}{ext}"[:max_total]
