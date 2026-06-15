#!/usr/bin/env python3
"""Gera fig-4-*.png a partir de docs/diagrams/ (fonte única). Não mantém fig-4-*.puml."""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT / "scripts" / "ci") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "scripts" / "ci"))

from diagram_sources import CANONICAL_DIR, MAPPING, REPORT_DIR, render_fig_puml  # noqa: E402


def check() -> int:
    errors = 0
    for source_name, fig_id in MAPPING:
        src = CANONICAL_DIR / source_name
        png = REPORT_DIR / f"{fig_id}.png"
        if not src.is_file():
            print(f"EM FALTA: {src.relative_to(REPO_ROOT)}", file=sys.stderr)
            errors += 1
            continue
        if not png.is_file():
            print(f"PNG EM FALTA: {png.relative_to(REPO_ROOT)} — execute render_plantuml.py", file=sys.stderr)
            errors += 1
            continue
        if png.stat().st_mtime < src.stat().st_mtime:
            print(f"DESATUALIZADO: {png.name} (fonte {source_name} mais recente)", file=sys.stderr)
            errors += 1
        else:
            print(f"OK {png.name}")
    return errors


def render() -> int:
    folder = Path(__file__).resolve().parent
    jar = folder / "plantuml.jar"
    if not jar.is_file():
        print(
            "plantuml.jar em falta. Descarregue de https://plantuml.com/download "
            f"e coloque em {jar}",
            file=sys.stderr,
        )
        return 1

    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    for source_name, fig_id in MAPPING:
        src = CANONICAL_DIR / source_name
        if not src.is_file():
            print(f"Em falta: {src}", file=sys.stderr)
            return 1

        content = render_fig_puml(source_name, fig_id)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".puml",
            delete=False,
            dir=folder,
        ) as tmp:
            tmp.write(content)
            tmp_path = Path(tmp.name)

        try:
            subprocess.run(
                ["java", "-jar", str(jar), "-tpng", str(tmp_path)],
                check=True,
                cwd=folder,
            )
            # PlantUML nomeia o PNG pelo @startuml id, não pelo ficheiro temporário
            generated = folder / f"{fig_id}.png"
            if not generated.is_file():
                generated = tmp_path.with_suffix(".png")
            target = REPORT_DIR / f"{fig_id}.png"
            if not generated.is_file():
                print(f"PNG não gerado para {fig_id}", file=sys.stderr)
                return 1
            if generated.resolve() != target.resolve():
                target.parent.mkdir(parents=True, exist_ok=True)
                generated.replace(target)
            print(f"OK {source_name} -> {target.name} ({target.stat().st_size} bytes)")
        finally:
            tmp_path.unlink(missing_ok=True)
            for orphan in folder.glob(f"{fig_id}*.png"):
                if orphan.resolve() != (REPORT_DIR / f"{fig_id}.png").resolve():
                    orphan.unlink(missing_ok=True)

    # Remover artefatos legados duplicados
    for legacy in REPORT_DIR.glob("fig-4-*.puml"):
        legacy.unlink()
        print(f"REMOVE legado {legacy.name}")

    return 0


def main() -> int:
    if "--check" in sys.argv:
        return check()
    return render()


if __name__ == "__main__":
    raise SystemExit(main())
