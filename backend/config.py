# --- Módulo: config ---
# Configuração central do RAT Analyzer: saídas/artefatos num diretório de dados
# do utilizador (por defeito em %LOCALAPPDATA%), com override por variável de ambiente.

from __future__ import annotations

import os
from pathlib import Path

# *Raiz do projeto (pasta PROJETO, acima de backend/)*
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# *Dados do analisador mantidos no repositório*
YARA_RULES_DIR = PROJECT_ROOT / "yara_rules"

# *Projeto de exemplo para testes manuais (GUI Tkinter — ver backend/gui/README.md)*
SAMPLE_PROJECT_DIR = PROJECT_ROOT / "programa"


# --- Diretório base de dados e artefatos ---
def _default_data_dir() -> Path:
    # *Prioridade: RATANALYZER_DATA_DIR > %LOCALAPPDATA%\RatAnalyzer > <repo>/data*
    env = (os.environ.get("RATANALYZER_DATA_DIR") or "").strip()
    if env:
        return Path(env).expanduser().resolve()

    local = (os.environ.get("LOCALAPPDATA") or "").strip()
    if local:
        return (Path(local) / "RatAnalyzer").resolve()

    return (PROJECT_ROOT / "data").resolve()


DATA_DIR = _default_data_dir()

# *Saídas geradas (não versionadas)*
REPORTS_DIR = DATA_DIR / "reports"
DECOMPILED_DIR = DATA_DIR / "decompiled"

# *Diretório base para jobs de análise (estática/dinâmica)*
SANDBOX_JOBS_DIR = DATA_DIR / "sandbox_jobs"

# *Base de dados SQLite para histórico/auditoria*
ANALYSIS_DB_PATH = SANDBOX_JOBS_DIR / "analysis.db"

# *Limites para extração de trechos obfuscados (evitar ficheiros enormes)*
OBFUSCATION_SNIPPETS_MAX = 50
OBFUSCATION_SNIPPET_MAX_LINES = 50
OBFUSCATION_CONTEXT_LINES = 3

# *Opções de poupança de espaço (defaults conservadores; não destrutivo por defeito)*
KEEP_ILSPY_TREE = os.environ.get("RATANALYZER_KEEP_ILSPY_TREE", "1").strip() not in ("0", "false", "False")
KEEP_GHIDRA_PROJECT = os.environ.get("RATANALYZER_KEEP_GHIDRA_PROJECT", "1").strip() not in ("0", "false", "False")

# *Retenção/arquivo (controlável por env vars; a UI também pode chamar endpoints)*
JOBS_RETENTION_DAYS = int(os.environ.get("RATANALYZER_JOBS_RETENTION_DAYS", "30"))
JOBS_MAX_COUNT = int(os.environ.get("RATANALYZER_JOBS_MAX_COUNT", "200"))
COLD_ARCHIVE_DAYS = int(os.environ.get("RATANALYZER_COLD_ARCHIVE_DAYS", "30"))
