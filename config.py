"""
Configuração central do RAT Analyzer.
Todos os caminhos e constantes do projeto num único sítio.
"""

from pathlib import Path

# Raiz do projeto (pasta onde estão rat_analyzer.py, config.py, modules/, etc.)
PROJECT_ROOT = Path(__file__).resolve().parent

# Saídas geradas (não versionadas)
REPORTS_DIR = PROJECT_ROOT / "reports"
DECOMPILED_DIR = PROJECT_ROOT / "decompiled"

# Dados do analisador
YARA_RULES_DIR = PROJECT_ROOT / "yara_rules"

# Projeto de exemplo para testes (opcional)
SAMPLE_PROJECT_DIR = PROJECT_ROOT / "programa"
