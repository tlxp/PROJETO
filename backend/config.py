"""
Configuração central do RAT Analyzer.
Todos os caminhos e constantes do projeto num único sítio.
"""

from pathlib import Path

# Raiz do projeto (pasta PROJETO, acima de backend/)
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Saídas geradas (não versionadas)
REPORTS_DIR = PROJECT_ROOT / "reports"
DECOMPILED_DIR = PROJECT_ROOT / "decompiled"

# Diretório base para jobs de análise (estática/dinâmica)
SANDBOX_JOBS_DIR = PROJECT_ROOT / "sandbox_jobs"

# Base de dados SQLite para histórico/auditoria (por defeito dentro de sandbox_jobs/)
ANALYSIS_DB_PATH = SANDBOX_JOBS_DIR / "analysis.db"

# Dados do analisador
YARA_RULES_DIR = PROJECT_ROOT / "yara_rules"

# Projeto de exemplo para testes (opcional)
SAMPLE_PROJECT_DIR = PROJECT_ROOT / "programa"

# Limites para extração de trechos obfuscados (evitar ficheiros enormes)
OBFUSCATION_SNIPPETS_MAX = 50
OBFUSCATION_SNIPPET_MAX_LINES = 50
OBFUSCATION_CONTEXT_LINES = 3
