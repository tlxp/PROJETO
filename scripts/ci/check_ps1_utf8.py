#!/usr/bin/env python3
"""
Valida que todos os .ps1 em scripts/ são UTF-8 válidos (com ou sem BOM).

Falha em:
  - bytes que não decodificam como UTF-8
  - carácter de substituição U+FFFD
  - sequências típicas de mojibake (UTF-8 lido como Latin-1)
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT / "scripts"

MOJIBAKE_MARKERS = (
    "Ã§",
    "Ã£",
    "Ã¡",
    "Ã©",
    "Ã­",
    "Ã³",
    "Ãº",
    "Ã‡",
    "â€",
    "ï¿½",
)


def decode_ps1(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig")
    return raw.decode("utf-8")


def main() -> int:
    if not SCRIPTS_DIR.is_dir():
        print(f"ERRO: pasta não encontrada: {SCRIPTS_DIR}", file=sys.stderr)
        return 1

    files = sorted(SCRIPTS_DIR.rglob("*.ps1"))
    if not files:
        print("AVISO: nenhum .ps1 encontrado em scripts/")
        return 0

    failed: list[str] = []
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        try:
            text = decode_ps1(path)
        except UnicodeDecodeError as exc:
            failed.append(f"{rel}: não é UTF-8 válido ({exc})")
            continue

        if "\ufffd" in text:
            failed.append(f"{rel}: contém U+FFFD (substituição)")
            continue

        for marker in MOJIBAKE_MARKERS:
            if marker in text:
                failed.append(f"{rel}: possível mojibake ({marker!r})")
                break

    if failed:
        print("Falha na validação UTF-8 dos scripts PowerShell:", file=sys.stderr)
        for line in failed:
            print(f"  - {line}", file=sys.stderr)
        return 1

    print(f"OK: {len(files)} ficheiros .ps1 com UTF-8 válido.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
