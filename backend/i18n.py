"""Mensagens de API/relatório localizadas (PT/EN)."""
from __future__ import annotations

import os
from typing import Optional

MESSAGES: dict[str, dict[str, str]] = {
    "pt": {
        "report_not_generated": "# Relatório não gerado.",
        "no_bytecode": "# Nenhum bytecode/assembly disponível para este ficheiro.",
        "job_not_found": "Job não encontrado.",
        "list_jobs_error": "Erro ao listar análises.",
        "snippets_not_available": "Ficheiro de trechos não disponível para este job.",
        "snippets_note": "Nota: Não foram extraídos trechos de código para este job (ex.: análise sem descompilação).",
        "code_not_available": "# Código não disponível.",
        "bytecode_not_available": "# Bytecode não disponível.",
    },
    "en": {
        "report_not_generated": "# Report not generated.",
        "no_bytecode": "# No bytecode/assembly available for this file.",
        "job_not_found": "Job not found.",
        "list_jobs_error": "Error listing analyses.",
        "snippets_not_available": "Snippets file not available for this job.",
        "snippets_note": "Note: No code snippets were extracted for this job (e.g. analysis without decompilation).",
        "code_not_available": "# Code not available.",
        "bytecode_not_available": "# Bytecode not available.",
    },
}


def resolve_lang(
    accept_language: Optional[str] = None,
    query_lang: Optional[str] = None,
    env_lang: Optional[str] = None,
) -> str:
    """Resolve idioma: query > env > Accept-Language > pt."""
    for candidate in (query_lang, env_lang):
        if candidate in ("en", "pt"):
            return candidate
    if accept_language and "en" in accept_language.lower():
        return "en"
    return "pt"


def current_lang() -> str:
    return resolve_lang(env_lang=os.environ.get("RATANALYZER_LANG"))


def t(key: str, lang: Optional[str] = None) -> str:
    lang = lang or current_lang()
    bucket = MESSAGES.get(lang) or MESSAGES["pt"]
    return bucket.get(key) or MESSAGES["pt"].get(key, key)
