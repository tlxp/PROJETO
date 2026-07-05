"""Pós-processamento de ficheiros .lock gerados pelo pip-compile.

Remove pacotes específicos de plataforma (ex.: colorama no Windows) para que
os locks coincidam com a validação do CI em ubuntu-latest.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def strip_platform_only_packages(text: str) -> str:
    # colorama é puxado por click/pytest apenas no Windows; o CI corre em Linux.
    return re.sub(
        r"\ncolorama==.*?(?=\n[a-zA-Z0-9])",
        "",
        text,
        count=1,
        flags=re.DOTALL,
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Uso: {sys.argv[0]} <origem> <destino>")

    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    text = strip_platform_only_packages(src.read_text(encoding="utf-8"))
    dst.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
