#!/usr/bin/env python3
"""Compute proxy detection metrics from labeled synthetic profiles."""

from __future__ import annotations

import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from modules.risk_scorer import RiskScorer  # noqa: E402

PROFILES_PATH = BACKEND_ROOT / "evaluation" / "proxy_labeled_profiles.json"
OUTPUT_PATH = BACKEND_ROOT / "evaluation" / "detection_metrics.json"

POSITIVE_LEVELS = frozenset({"ALTO", "CRÍTICO"})


def _predict_malicious(level: str) -> bool:
    return level in POSITIVE_LEVELS


def _load_profiles() -> dict:
    with PROFILES_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def compute_metrics() -> dict:
    data = _load_profiles()
    scorer = RiskScorer()
    rows: list[dict] = []
    tp = tn = fp = fn = 0

    for profile in data["profiles"]:
        result = scorer.calculate_risk(
            profile["static"],
            profile.get("yara", []),
            profile.get("deobf", {"obfuscation_indicators": []}),
        )
        expected_malicious = profile["label"] == "malicious"
        predicted_malicious = _predict_malicious(result["level"])

        if expected_malicious and predicted_malicious:
            tp += 1
        elif not expected_malicious and not predicted_malicious:
            tn += 1
        elif not expected_malicious and predicted_malicious:
            fp += 1
        else:
            fn += 1

        rows.append(
            {
                "id": profile["id"],
                "label": profile["label"],
                "score": result["score"],
                "level": result["level"],
                "predicted_malicious": predicted_malicious,
                "correct": expected_malicious == predicted_malicious,
            }
        )

    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    accuracy = (tp + tn) / len(rows) if rows else 0.0

    return {
        "methodology": (
            "Proxy metrics on labeled synthetic static profiles (no real malware binaries). "
            "Positive prediction: risk level ALTO or CRITICO."
        ),
        "profiles_path": str(PROFILES_PATH.relative_to(BACKEND_ROOT.parent)),
        "n_profiles": len(rows),
        "confusion_matrix": {"tp": tp, "tn": tn, "fp": fp, "fn": fn},
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1": round(f1, 3),
        "accuracy": round(accuracy, 3),
        "profiles": rows,
    }


def main() -> int:
    metrics = compute_metrics()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2, ensure_ascii=False)
    print(json.dumps(metrics, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
