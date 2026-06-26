#!/usr/bin/env python3
# --- Módulo: check_md_links ---
# --- Valida Markdown: links, ortografia PT, H1 único e espaços finais ---

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SKIP_DIR_NAMES = frozenset(
    {
        "node_modules",
        "bin",
        "obj",
        "publish",
        ".git",
        "__pycache__",
        ".pytest_cache",
    }
)

CODE_TEXT_SUFFIXES = frozenset({".py", ".ps1", ".cs", ".ts", ".tsx", ".xaml", ".tex"})

BINARY_SUFFIXES = frozenset(
    {
        ".jar",
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".exe",
        ".dll",
        ".pdb",
        ".ico",
        ".woff",
        ".woff2",
    }
)

SKIP_FILES = frozenset({"scripts/ci/check_md_links.py"})

# Documentos históricos em docs/archive/ (exceto README.md) não seguem regras de estilo atuais.
ARCHIVE_MD_LINT_PREFIX = "docs/archive/"


def _skip_md_style_lint(rel: Path) -> bool:
    posix = rel.as_posix()
    if posix == "docs/archive/README.md":
        return False
    return posix.startswith(ARCHIVE_MD_LINT_PREFIX)

LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")

# Formas pré-acordo a evitar em .md (grafia com «c» onde o acordo omite).
LEGACY_MD_RE = re.compile(
    r"\b(?:"
    r"secção|secções|"
    r"actual|"
    r"Acção|"
    r"desactive|"
    r"reflecte|"
    r"Excepções|Excepção|"
    r"artefactos?|Artefactos?|ARTEFACTOS?"
    r")\b"
)

FENCE_RE = re.compile(r"^\s*```")

# Grafia legada «artefacto» apenas em ficheiros de código/comentários.
LEGACY_ARTEFACTO_RE = re.compile(
    r"\b(?:artefactos?|Artefactos?|ARTEFACTOS?)\b"
)


def should_skip_dir(path: Path) -> bool:
    return path.name in SKIP_DIR_NAMES


def _is_skipped(rel: Path) -> bool:
    posix = rel.as_posix()
    return posix in SKIP_FILES or any(part in SKIP_DIR_NAMES for part in rel.parts)


def iter_md_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*.md"):
        rel = path.relative_to(ROOT)
        if _is_skipped(rel):
            continue
        files.append(path)
    return sorted(files)


def iter_code_text_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if _is_skipped(rel):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        if path.suffix.lower() in CODE_TEXT_SUFFIXES:
            files.append(path)
    return sorted(files)


def resolve_link(source: Path, target: str) -> Path | None:
    if target.startswith(("http://", "https://", "mailto:")):
        return None
    if target.startswith("#"):
        return None
    path_part, _, _ = target.partition("#")
    if not path_part:
        return None
    if path_part.startswith("/"):
        return ROOT / path_part.lstrip("/")
    return (source.parent / path_part).resolve()


def link_exists(target: Path, raw: str) -> bool:
    if raw.endswith("/"):
        return target.is_dir() or target.with_suffix(".md").is_file()
    return target.exists()


def check_links() -> list[str]:
    errors: list[str] = []
    for md in iter_md_files():
        rel = md.relative_to(ROOT).as_posix()
        for match in LINK_RE.finditer(md.read_text(encoding="utf-8", errors="replace")):
            raw = match.group(2).strip()
            path_part = raw.split("#")[0]
            if not path_part or path_part.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = resolve_link(md, path_part)
            if resolved is None:
                continue
            if not link_exists(resolved, path_part):
                errors.append(f"link partido: {rel} -> {raw} (resolvido: {resolved.as_posix()})")
    return errors


def check_legacy_md() -> list[str]:
    errors: list[str] = []
    for md in iter_md_files():
        rel = md.relative_to(ROOT)
        if _skip_md_style_lint(rel):
            continue
        rel_posix = rel.as_posix()
        for lineno, line in enumerate(
            md.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
        ):
            if LEGACY_MD_RE.search(line):
                errors.append(f"ortografia legada: {rel_posix}:{lineno}: {line.strip()}")
    return errors


def _h1_lines_outside_fences(text: str) -> list[tuple[int, str]]:
    in_fence = False
    h1s: list[tuple[int, str]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence and line.startswith("# ") and not line.startswith("##"):
            h1s.append((lineno, line.strip()))
    return h1s


def check_single_h1() -> list[str]:
    errors: list[str] = []
    for md in iter_md_files():
        rel = md.relative_to(ROOT)
        if _skip_md_style_lint(rel):
            continue
        rel_posix = rel.as_posix()
        h1s = _h1_lines_outside_fences(md.read_text(encoding="utf-8", errors="replace"))
        if len(h1s) > 1:
            lines = ", ".join(f"L{lineno}" for lineno, _ in h1s)
            errors.append(f"múltiplos H1: {rel_posix} ({lines})")
    return errors


def check_trailing_whitespace() -> list[str]:
    errors: list[str] = []
    for md in iter_md_files():
        rel = md.relative_to(ROOT)
        if _skip_md_style_lint(rel):
            continue
        rel_posix = rel.as_posix()
        for lineno, line in enumerate(
            md.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
        ):
            if line.endswith(" ") or line.endswith("\t"):
                errors.append(f"espaço no fim da linha: {rel_posix}:{lineno}")
    return errors


def check_legacy_artefacto_in_code() -> list[str]:
    errors: list[str] = []
    for path in iter_code_text_files():
        rel = path.relative_to(ROOT).as_posix()
        try:
            text = path.read_text(encoding="utf-8", errors="strict")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            if LEGACY_ARTEFACTO_RE.search(line):
                errors.append(f"artefacto legado: {rel}:{lineno}: {line.strip()}")
    return errors


def main() -> int:
    errors = (
        check_links()
        + check_legacy_md()
        + check_single_h1()
        + check_trailing_whitespace()
        + check_legacy_artefacto_in_code()
    )

    if errors:
        print(f"ERRO: {len(errors)} problema(s) encontrado(s):\n", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(iter_md_files())} ficheiros .md - links, ortografia, H1, "
        "espaços finais e artefato(s) validados."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
