# --- Módulo: run_evaluation_metrics.py ---
# Métricas proxy de deteção a partir de perfis sintéticos etiquetados (sem malware real).

from __future__ import annotations

import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from evaluation.metrics_core import DEFAULT_PROFILES_PATH, POSITIVE_LEVELS, compute_metrics  # noqa: E402

PROFILES_PATH = DEFAULT_PROFILES_PATH
__all__ = ["PROFILES_PATH", "POSITIVE_LEVELS", "compute_metrics"]
OUTPUT_PATH = BACKEND_ROOT / "evaluation" / "detection_metrics.json"


# --- Ponto de entrada: grava detection_metrics.json ---
def main() -> int:
    metrics = compute_metrics(profiles_path=PROFILES_PATH)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2, ensure_ascii=False)
    print(json.dumps(metrics, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
