# --- Módulo: test_evaluation_metrics ---
# Testes das métricas proxy de deteção (perfis sintéticos etiquetados).
from pathlib import Path

from scripts.run_evaluation_metrics import compute_metrics, PROFILES_PATH


def test_proxy_profiles_file_exists():
    assert PROFILES_PATH.is_file()


def test_proxy_metrics_perfect_on_labeled_set():
    metrics = compute_metrics()
    assert metrics["n_profiles"] == 5
    cm = metrics["confusion_matrix"]
    assert cm["fp"] == 0
    assert cm["fn"] == 0
    assert metrics["precision"] == 1.0
    assert metrics["recall"] == 1.0
    assert metrics["f1"] == 1.0
