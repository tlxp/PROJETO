#!/usr/bin/env python3
"""
Limpa caches, artefatos de testes e ficheiros temporários gerados.

Não remove: código fonte (.cs em programa/), relatórios versionados, regras YARA.

Remove:
  - __pycache__, .pytest_cache (raiz, backend/ e subpastas)
  - *.pyc / *.pyo
  - programa/**/bin e programa/**/obj
  - decompiled canónico em DATA_DIR (config.DECOMPILED_DIR)
  - decompiled/ legado na raiz do repo (versões antigas, pré-DATA_DIR)
"""

import shutil
import sys
from pathlib import Path

import config

ROOT = config.PROJECT_ROOT

_SKIP_DIR_NAMES = frozenset(
    {
        ".git",
        "node_modules",
        ".venv",
        "venv",
        "env",
        "dist",
        "frontend/dist",
    }
)


def _skip_path(path: Path) -> bool:
    return any(part in _SKIP_DIR_NAMES for part in path.parts)


def count_items(path: Path) -> int:
    """Conta ficheiros e pastas (recursivo para diretórios)."""
    if not path.exists():
        return 0
    if path.is_file():
        return 1
    return sum(1 for _ in path.rglob("*"))


def _decompiled_targets() -> list[Path]:
    """Pastas decompiladas: DATA_DIR (canónico) + legado na raiz do repo."""
    targets = [config.DECOMPILED_DIR]
    legacy = ROOT / "decompiled"
    if legacy.resolve() not in {t.resolve() for t in targets}:
        targets.append(legacy)
    return targets


def main() -> int:
    dry_run = "--dry-run" in sys.argv or "-n" in sys.argv
    if dry_run:
        print("Modo dry-run: nada será apagado.\n")

    removed = 0

    # 1) Python: __pycache__ (evitar .git)
    pycache_dirs = [
        d for d in ROOT.rglob("__pycache__")
        if d.is_dir() and not _skip_path(d)
    ]
    for d in pycache_dirs:
        c = count_items(d)
        print(f"  Remover: {d.relative_to(ROOT)} ({c} itens)")
        removed += c
        if not dry_run:
            shutil.rmtree(d)

    # 2) pytest cache (raiz, backend/, etc.)
    pytest_caches = [
        d for d in ROOT.rglob(".pytest_cache")
        if d.is_dir() and not _skip_path(d)
    ]
    for cache in sorted(pytest_caches, key=lambda p: len(p.parts), reverse=True):
        c = count_items(cache)
        print(f"  Remover: {cache.relative_to(ROOT)} ({c} itens)")
        removed += c
        if not dry_run:
            shutil.rmtree(cache)

    # 3) .pyc, .pyo (evitar .git)
    py_files = [
        f for ext in ("*.pyc", "*.pyo")
        for f in ROOT.rglob(ext)
        if f.is_file() and not _skip_path(f)
    ]
    for f in py_files:
        print(f"  Remover: {f.relative_to(ROOT)}")
        removed += 1
        if not dry_run:
            f.unlink()

    # 4) programa/**/bin e programa/**/obj (build e exe/dll gerados)
    if config.SAMPLE_PROJECT_DIR.is_dir():
        for name in ("bin", "obj"):
            for d in config.SAMPLE_PROJECT_DIR.rglob(name):
                if d.is_dir() and d.name == name and not _skip_path(d):
                    c = count_items(d)
                    print(f"  Remover: {d.relative_to(ROOT)} ({c} itens)")
                    removed += c
                    if not dry_run:
                        shutil.rmtree(d)

    # 5) decompiled (DATA_DIR + legado na raiz)
    for decompiled_dir in _decompiled_targets():
        if decompiled_dir.exists():
            c = count_items(decompiled_dir)
            label = decompiled_dir.relative_to(ROOT) if decompiled_dir.is_relative_to(ROOT) else decompiled_dir
            print(f"  Remover: {label} ({c} itens)")
            removed += c
            if not dry_run:
                shutil.rmtree(decompiled_dir)

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
