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

# Dados do analisador
YARA_RULES_DIR = PROJECT_ROOT / "yara_rules"

# Projeto de exemplo para testes (opcional)
SAMPLE_PROJECT_DIR = PROJECT_ROOT / "programa"
