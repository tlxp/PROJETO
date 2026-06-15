"""
Configuração partilhada dos testes.

IMPORTANTE: RATANALYZER_DATA_DIR tem de ser definido ANTES de importar
config/api/analysis_jobs (os paths são resolvidos no import do config).
"""

import os
import sys
import tempfile
from pathlib import Path

# Backend no sys.path
_BACKEND = Path(__file__).resolve().parent.parent
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

# Dados de teste isolados (sandbox_jobs, reports, DB SQLite, etc.)
_TEST_DATA_DIR = tempfile.mkdtemp(prefix="ratanalyzer_tests_")
os.environ["RATANALYZER_DATA_DIR"] = _TEST_DATA_DIR


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "integration: testes que exigem sandbox/VM real (RUN_VM_DRIVER_INTEGRATION=1)",
    )
