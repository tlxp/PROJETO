#!/usr/bin/env python3
"""
Limpa caches, artefactos de testes e ficheiros temporários gerados.
Não remove: código fonte (.cs em programa/), relatórios (reports/), regras YARA.
Remove: __pycache__, .pytest_cache, programa/bin, programa/obj, decompiled/.
"""

import shutil
import sys
from pathlib import Path

import config

ROOT = config.PROJECT_ROOT


def count_items(path: Path) -> int:
    """Conta ficheiros e pastas (apenas um nível para pastas)."""
    if not path.exists():
        return 0
    if path.is_file():
        return 1
    return sum(1 for _ in path.rglob("*"))


def remove_dir(path: Path, dry_run: bool) -> int:
    if not path.exists() or not path.is_dir():
        return 0
    n = count_items(path)
    if not dry_run:
        shutil.rmtree(path)
    return n


def remove_file(path: Path, dry_run: bool) -> bool:
    if not path.exists() or not path.is_file():
        return False
    if not dry_run:
        path.unlink()
    return True


def main() -> int:
    dry_run = "--dry-run" in sys.argv or "-n" in sys.argv
    if dry_run:
        print("Modo dry-run: nada será apagado.\n")

    removed = 0

    # 1) Python: __pycache__ (evitar .git)
    pycache_dirs = [
        d for d in ROOT.rglob("__pycache__")
        if d.is_dir() and ".git" not in d.parts
    ]
    for d in pycache_dirs:
        c = count_items(d)
        print(f"  Remover: {d.relative_to(ROOT)} ({c} itens)")
        removed += c
        if not dry_run:
            shutil.rmtree(d)

    # 2) pytest cache
    pytest_cache = ROOT / ".pytest_cache"
    if pytest_cache.exists():
        c = count_items(pytest_cache)
        print(f"  Remover: .pytest_cache ({c} itens)")
        removed += c
        if not dry_run:
            shutil.rmtree(pytest_cache)

    # 3) .pyc, .pyo (evitar .git)
    py_files = [
        f for ext in ("*.pyc", "*.pyo")
        for f in ROOT.rglob(ext)
        if f.is_file() and ".git" not in f.parts
    ]
    for f in py_files:
        print(f"  Remover: {f.relative_to(ROOT)}")
        removed += 1
        if not dry_run:
            f.unlink()

    # 4) programa/bin e programa/obj (build e exe/dll gerados)
    for name in ("bin", "obj"):
        d = config.SAMPLE_PROJECT_DIR / name
        if d.exists():
            c = count_items(d)
            print(f"  Remover: programa/{name}/ ({c} itens)")
            removed += c
            if not dry_run:
                shutil.rmtree(d)

    # 5) decompiled/ (código descompilado e projetos Ghidra temporários)
    if config.DECOMPILED_DIR.exists():
        c = count_items(config.DECOMPILED_DIR)
        print(f"  Remover: decompiled/ ({c} itens)")
        removed += c
        if not dry_run:
            shutil.rmtree(config.DECOMPILED_DIR)

    if dry_run and removed == 0:
        print("Nada a remover.")
    elif dry_run:
        print(f"\nTotal (dry-run): {removed} itens seriam removidos.")
    else:
        print(f"\nLimpeza concluída. {removed} itens removidos.")

    return 0


if __name__ == "__main__":
    print("A limpar caches e ficheiros temporários...")
    sys.exit(main())
