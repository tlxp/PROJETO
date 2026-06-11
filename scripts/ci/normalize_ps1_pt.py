#!/usr/bin/env python3
"""
Normaliza mensagens PT-PT em .ps1: acentos em palavras comuns e UTF-8 com BOM + CRLF.

Uso (raiz do repo):
  python scripts/ci/normalize_ps1_pt.py          # aplica
  python scripts/ci/normalize_ps1_pt.py --check  # só reporta diferenças (exit 1 se houver)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT / "scripts"

# Frases compostas primeiro (evita substituições parciais).
PHRASE_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    (r"\bja nao\b", "já não"),
    (r"\bJa nao\b", "Já não"),
    (r"\bainda nao\b", "ainda não"),
    (r"\bAinda nao\b", "Ainda não"),
)

WORD_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    (r"\bnao\b", "não"),
    (r"\bNao\b", "Não"),
    (r"\bNAO\b", "NÃO"),
    (r"\bconfiguracao\b", "configuração"),
    (r"\bConfiguracao\b", "Configuração"),
    (r"\bservico\b", "serviço"),
    (r"\bServico\b", "Serviço"),
    (r"\bservicos\b", "serviços"),
    (r"\bServicos\b", "Serviços"),
    (r"\bpossivel\b", "possível"),
    (r"\bPossivel\b", "Possível"),
    (r"\binstalacao\b", "instalação"),
    (r"\bInstalacao\b", "Instalação"),
    (r"\binjecao\b", "injeção"),
    (r"\bInjecao\b", "Injeção"),
    (r"\binicio\b", "início"),
    (r"\bInicio\b", "Início"),
    (r"\brelatorio\b", "relatório"),
    (r"\bRelatorio\b", "Relatório"),
    (r"\bautomatica\b", "automática"),
    (r"\bautomatico\b", "automático"),
    (r"\bproducao\b", "produção"),
    (r"\binstrucoes\b", "instruções"),
    (r"\borquestracao\b", "orquestração"),
    (r"\bintegracao\b", "integração"),
    (r"\bnecessaria\b", "necessária"),
    (r"\bNecessaria\b", "Necessária"),
    (r"\bnecessarios\b", "necessários"),
    (r"\bNecessarios\b", "Necessários"),
)

SKIP_PARTS = ("tools/winutil.ps1",)


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig")
    return raw.decode("utf-8")


def normalize_content(text: str) -> str:
    out = text.replace("\r\n", "\n").replace("\r", "\n")
    for pattern, repl in PHRASE_REPLACEMENTS:
        out = re.sub(pattern, repl, out)
    for pattern, repl in WORD_REPLACEMENTS:
        out = re.sub(pattern, repl, out)
    return out.replace("\n", "\r\n")


def should_skip(rel: str) -> bool:
    return any(part in rel.replace("\\", "/") for part in SKIP_PARTS)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="não escreve; falha se houver alterações")
    args = parser.parse_args()

    changed: list[str] = []
    for path in sorted(SCRIPTS_DIR.rglob("*.ps1")):
        rel = path.relative_to(ROOT).as_posix()
        if should_skip(rel):
            continue
        try:
            original = read_text(path)
        except UnicodeDecodeError:
            print(f"SKIP (encoding inválido): {rel}", file=sys.stderr)
            continue

        normalized = normalize_content(original)
        # Reconstroi bytes esperados: UTF-8 BOM + CRLF
        expected = normalized.encode("utf-8-sig")
        current = original.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n").encode("utf-8-sig")

        if expected != current:
            changed.append(rel)
            if not args.check:
                path.write_bytes(expected)

    if changed:
        mode = "seriam alterados" if args.check else "normalizados"
        print(f"{len(changed)} ficheiros {mode}:")
        for rel in changed:
            print(f"  - {rel}")
        return 1 if args.check else 0

    print("Nenhuma alteração necessária.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
