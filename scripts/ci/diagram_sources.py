"""Fonte única de diagramas PlantUML — docs/diagrams/ -> relatório/imagens/fig-4-*.png."""
from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CANONICAL_DIR = REPO_ROOT / "docs" / "diagrams"
REPORT_DIR = REPO_ROOT / "relatório" / "imagens"

# (ficheiro canónico, nome PNG/PDF no relatório LaTeX)
MAPPING: list[tuple[str, str]] = [
    ("analysis-usecase.puml", "fig-4-1-usecase"),
    ("analysis-activity-static.puml", "fig-4-2-activity-static"),
    ("analysis-activity-dynamic.puml", "fig-4-3-activity-dynamic"),
    ("analysis-architecture.puml", "fig-4-4-architecture"),
    ("analysis-sequence-overview.puml", "fig-4-5-sequence-overview"),
    ("security-trust-zones.puml", "fig-4-6-security-trust-zones"),
    ("sandbox-paths-comparison.puml", "fig-4-7-sandbox-paths"),
    ("sequence-path-a-vmagent.puml", "fig-4-8-sequence-path-a"),
    ("sequence-path-b-powershell.puml", "fig-4-9-sequence-path-b"),
    ("security-auth-tokens.puml", "fig-4-10-security-auth"),
]

_STARTUML_LINE_RE = re.compile(r"^@startuml\b.*\r?\n?", re.MULTILINE)


def body_without_startuml(text: str) -> str:
    lines = text.splitlines(keepends=True)
    if lines and lines[0].lstrip().startswith("@startuml"):
        return "".join(lines[1:]).lstrip("\n")
    return _STARTUML_LINE_RE.sub("", text, count=1).lstrip("\n")


def render_fig_puml(source_name: str, fig_id: str) -> str:
    canonical = (CANONICAL_DIR / source_name).read_text(encoding="utf-8")
    body = body_without_startuml(canonical)
    return f"@startuml {fig_id}\n{body}"
