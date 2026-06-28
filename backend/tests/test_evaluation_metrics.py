# --- Módulo: test_evaluation_metrics ---
# Testes das métricas proxy de deteção (perfis sintéticos etiquetados).

import json
import subprocess
import sys
from pathlib import Path

from evaluation.metrics_core import (
    POSITIVE_LEVELS,
    SEVERITY_LEVELS,
    collect_failures,
    compute_metrics,
    load_profiles,
    predict_malicious,
    score_profile,
)
from modules.risk_scorer import RiskScorer
from scripts.run_evaluation_metrics import PROFILES_PATH, compute_metrics as script_compute_metrics

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SYNTHETIC_EVAL_SCRIPT = BACKEND_ROOT / "scripts" / "run_synthetic_eval.py"


def test_proxy_profiles_file_exists():
    assert PROFILES_PATH.is_file()


def test_load_profiles_returns_expected_structure():
    data = load_profiles()
    assert "profiles" in data
    assert isinstance(data["profiles"], list)
    assert len(data["profiles"]) >= 1


def test_positive_levels_constant():
    assert POSITIVE_LEVELS == frozenset({"ALTO", "CRÍTICO"})
    assert predict_malicious("ALTO") is True
    assert predict_malicious("CRÍTICO") is True
    assert predict_malicious("MÉDIO") is False


def test_score_profile_returns_risk_fields():
    data = load_profiles()
    scorer = RiskScorer()
    result = score_profile(data["profiles"][0], scorer)
    assert "score" in result
    assert "level" in result
    assert result["level"] in SEVERITY_LEVELS


def test_proxy_metrics_perfect_on_labeled_set():
    data = load_profiles()
    metrics = compute_metrics(data)
    n_profiles = len(data["profiles"])
    assert metrics["n_profiles"] == n_profiles
    cm = metrics["confusion_matrix"]
    assert cm["fp"] == 0
    assert cm["fn"] == 0
    assert metrics["precision"] == 1.0
    assert metrics["recall"] == 1.0
    assert metrics["f1"] == 1.0


def test_severity_breakdown_structure():
    metrics = compute_metrics()
    breakdown = metrics["severity_breakdown"]
    assert set(breakdown.keys()) == set(SEVERITY_LEVELS)
    for level in SEVERITY_LEVELS:
        entry = breakdown[level]
        assert set(entry.keys()) == {
            "predicted_count",
            "expected_count",
            "profile_ids_predicted",
            "profile_ids_expected",
        }
        assert entry["predicted_count"] == len(entry["profile_ids_predicted"])
        assert entry["expected_count"] == len(entry["profile_ids_expected"])
    total_predicted = sum(b["predicted_count"] for b in breakdown.values())
    assert total_predicted == metrics["n_profiles"]


def test_level_accuracy_on_expanded_set():
    metrics = compute_metrics()
    la = metrics["level_accuracy"]
    assert la["n_with_expected_level"] == metrics["n_profiles"]
    assert la["n_level_match"] == metrics["n_profiles"]
    assert la["accuracy"] == 1.0


def test_level_accuracy_with_expected_level():
    data = load_profiles()
    profile = dict(data["profiles"][0])
    profile["expected_level"] = profile.get("expected_level", "MUITO BAIXO")
    metrics = compute_metrics({"profiles": [profile]})
    la = metrics["level_accuracy"]
    assert la["n_with_expected_level"] == 1
    assert la["accuracy"] in {0.0, 1.0}


def test_script_compute_metrics_backward_compatible():
    metrics = script_compute_metrics(profiles_path=PROFILES_PATH)
    assert "confusion_matrix" in metrics
    assert "severity_breakdown" in metrics
    assert "level_accuracy" in metrics
    assert "profiles" in metrics


def test_collect_failures_empty_on_perfect_set():
    metrics = compute_metrics()
    assert collect_failures(metrics["profiles"]) == []


def test_run_synthetic_eval_exit_code_success():
    result = subprocess.run(
        [sys.executable, str(SYNTHETIC_EVAL_SCRIPT)],
        cwd=str(BACKEND_ROOT.parent),
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["all_labels_correct"] is True


def test_run_synthetic_eval_exit_code_on_label_mismatch(tmp_path):
    data = load_profiles()
    tampered = json.loads(json.dumps(data))
    tampered["profiles"][0]["label"] = "malicious"
    profiles_file = tmp_path / "tampered_profiles.json"
    profiles_file.write_text(json.dumps(tampered), encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(SYNTHETIC_EVAL_SCRIPT), "--profiles-path", str(profiles_file)],
        cwd=str(BACKEND_ROOT.parent),
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1, result.stdout
