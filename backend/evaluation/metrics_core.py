# --- Módulo: metrics_core ---
# Lógica partilhada para métricas de avaliação em perfis sintéticos etiquetados.

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from modules.risk_scorer import RiskScorer

BACKEND_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILES_PATH = BACKEND_ROOT / "evaluation" / "proxy_labeled_profiles.json"

POSITIVE_LEVELS = frozenset({"ALTO", "CRÍTICO"})
SEVERITY_LEVELS = ("MUITO BAIXO", "BAIXO", "MÉDIO", "ALTO", "CRÍTICO")


# --- Predição maliciosa a partir do nível de risco ---
def predict_malicious(level: str) -> bool:
    return level in POSITIVE_LEVELS


# --- Carrega perfis etiquetados do JSON ---
def load_profiles(path: Path | None = None) -> dict:
    profiles_path = path or DEFAULT_PROFILES_PATH
    with profiles_path.open(encoding="utf-8") as f:
        return json.load(f)


# --- Pontua um perfil com RiskScorer ---
def score_profile(profile: dict, scorer: RiskScorer) -> dict:
    return scorer.calculate_risk(
        profile["static"],
        profile.get("yara", []),
        profile.get("deobf", {"obfuscation_indicators": []}),
    )


def _iter_profiles(profiles: dict | list[dict]) -> list[dict]:
    if isinstance(profiles, list):
        return profiles
    return profiles["profiles"]


def _evaluate_profile(profile: dict, scorer: RiskScorer) -> dict:
    result = score_profile(profile, scorer)
    level = result["level"]
    expected_malicious = profile["label"] == "malicious"
    predicted_malicious = predict_malicious(level)
    expected_level = profile.get("expected_level")

    row: dict[str, Any] = {
        "id": profile["id"],
        "label": profile["label"],
        "score": result["score"],
        "level": level,
        "predicted_malicious": predicted_malicious,
        "correct": expected_malicious == predicted_malicious,
    }
    if expected_level is not None:
        row["expected_level"] = expected_level
        row["level_correct"] = expected_level == level
    return row


# --- Breakdown por nível de severidade previsto/esperado ---
def _severity_breakdown(rows: list[dict]) -> dict[str, dict]:
    breakdown: dict[str, dict] = {}
    for severity in SEVERITY_LEVELS:
        predicted_ids = [r["id"] for r in rows if r["level"] == severity]
        expected_ids = [
            r["id"] for r in rows if r.get("expected_level") == severity
        ]
        breakdown[severity] = {
            "predicted_count": len(predicted_ids),
            "expected_count": len(expected_ids),
            "profile_ids_predicted": predicted_ids,
            "profile_ids_expected": expected_ids,
        }
    return breakdown


# --- Precisão de nível quando expected_level está presente ---
def _level_accuracy(rows: list[dict]) -> dict:
    with_expected = [r for r in rows if "expected_level" in r]
    n_match = sum(1 for r in with_expected if r.get("level_correct"))
    n_total = len(with_expected)
    return {
        "n_with_expected_level": n_total,
        "n_level_match": n_match,
        "accuracy": round(n_match / n_total, 3) if n_total else None,
    }


# --- Calcula matriz de confusão e métricas completas ---
def compute_metrics(
    profiles: dict | list[dict] | None = None,
    *,
    profiles_path: Path | None = None,
    scorer: RiskScorer | None = None,
) -> dict:
    if profiles is None:
        data = load_profiles(profiles_path)
        profiles_path = profiles_path or DEFAULT_PROFILES_PATH
    elif isinstance(profiles, dict):
        data = profiles
        profiles_path = profiles_path or DEFAULT_PROFILES_PATH
    else:
        data = {"profiles": profiles}
        profiles_path = profiles_path or DEFAULT_PROFILES_PATH

    scorer = scorer or RiskScorer()
    profile_list = _iter_profiles(data)
    rows: list[dict] = []
    tp = tn = fp = fn = 0

    for profile in profile_list:
        row = _evaluate_profile(profile, scorer)
        expected_malicious = row["label"] == "malicious"
        predicted_malicious = row["predicted_malicious"]

        if expected_malicious and predicted_malicious:
            tp += 1
        elif not expected_malicious and not predicted_malicious:
            tn += 1
        elif not expected_malicious and predicted_malicious:
            fp += 1
        else:
            fn += 1

        rows.append(row)

    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    accuracy = (tp + tn) / len(rows) if rows else 0.0

    try:
        rel_path = str(profiles_path.relative_to(BACKEND_ROOT.parent))
    except ValueError:
        rel_path = str(profiles_path)

    return {
        "methodology": (
            "Métricas proxy em perfis estáticos sintéticos etiquetados (sem binários maliciosos). "
            "Predição positiva: nível ALTO ou CRÍTICO."
        ),
        "profiles_path": rel_path,
        "n_profiles": len(rows),
        "confusion_matrix": {"tp": tp, "tn": tn, "fp": fp, "fn": fn},
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1": round(f1, 3),
        "accuracy": round(accuracy, 3),
        "severity_breakdown": _severity_breakdown(rows),
        "level_accuracy": _level_accuracy(rows),
        "profiles": rows,
    }


# --- Falhas de etiqueta (FP/FN) e de nível esperado ---
def collect_failures(rows: list[dict]) -> list[dict]:
    failures: list[dict] = []
    for row in rows:
        kinds: list[str] = []
        if row["label"] == "benign" and row["predicted_malicious"]:
            kinds.append("fp")
        elif row["label"] == "malicious" and not row["predicted_malicious"]:
            kinds.append("fn")
        if row.get("expected_level") is not None and not row.get("level_correct", True):
            kinds.append("level_mismatch")

        if kinds:
            detail: dict[str, Any] = {
                "id": row["id"],
                "kinds": kinds,
                "label": row["label"],
                "level": row["level"],
                "score": row["score"],
                "predicted_malicious": row["predicted_malicious"],
            }
            if "expected_level" in row:
                detail["expected_level"] = row["expected_level"]
            failures.append(detail)
    return failures
