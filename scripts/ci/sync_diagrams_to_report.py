#!/usr/bin/env python3
"""Compat: use relatório/imagens/render_plantuml.py --check ou render direto."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

RENDER = Path(__file__).resolve().parents[2] / "relatório" / "imagens" / "render_plantuml.py"


def main() -> int:
    args = [sys.executable, str(RENDER)]
    if "--check" in sys.argv:
        args.append("--check")
    return subprocess.call(args)


if __name__ == "__main__":
    raise SystemExit(main())
