# --- Módulo: run_synthetic_eval.py ---
# Avaliação abrangente de perfis sintéticos etiquetados via RiskScorer.

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from evaluation.metrics_core import (  # noqa: E402
    DEFAULT_PROFILES_PATH,
    collect_failures,
    compute_metrics,
    load_profiles,
)

OUTPUT_PATH = BACKEND_ROOT / "evaluation" / "synthetic_eval_results.json"


def _build_results(metrics: dict) -> dict:
    rows = metrics["profiles"]
    failures = collect_failures(rows)
    cm = metrics["confusion_matrix"]
    label_mismatches = cm["fp"] + cm["fn"]

    return {
        "methodology": metrics["methodology"],
        "profiles_path": metrics["profiles_path"],
        "n_profiles": len(rows),
        "confusion_matrix": cm,
        "precision": metrics["precision"],
        "recall": metrics["recall"],
        "f1": metrics["f1"],
        "accuracy": metrics["accuracy"],
        "severity_breakdown": metrics["severity_breakdown"],
        "level_accuracy": metrics["level_accuracy"],
        "label_mismatches": label_mismatches,
        "profiles": rows,
        "failures": failures,
        "all_labels_correct": label_mismatches == 0,
    }


def _print_results(results: dict, *, verbose: bool, failures_only: bool) -> None:
    if failures_only:
        payload = {"failures": results["failures"], "label_mismatches": results["label_mismatches"]}
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return

    if verbose:
        print(json.dumps(results, indent=2, ensure_ascii=False))
        return

    summary = {
        "n_profiles": results["n_profiles"],
        "confusion_matrix": results["confusion_matrix"],
        "precision": results["precision"],
        "recall": results["recall"],
        "f1": results["f1"],
        "accuracy": results["accuracy"],
        "severity_breakdown": results["severity_breakdown"],
        "level_accuracy": results["level_accuracy"],
        "label_mismatches": results["label_mismatches"],
        "n_failures": len(results["failures"]),
        "all_labels_correct": results["all_labels_correct"],
    }
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    if results["failures"]:
        print("\nFalhas:", file=sys.stderr)
        for failure in results["failures"]:
            kinds = ", ".join(failure["kinds"])
            print(f"  - {failure['id']}: {kinds}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Avaliação sintética de perfis etiquetados com RiskScorer",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Imprime JSON completo com todos os perfis",
    )
    parser.add_argument(
        "--failures-only",
        action="store_true",
        help="Imprime apenas falhas (FP, FN, level mismatch)",
    )
    parser.add_argument(
        "--profile",
        metavar="ID",
        help="Avalia apenas o perfil com este id",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=OUTPUT_PATH,
        help=f"Caminho do ficheiro de resultados (predefinido: {OUTPUT_PATH.name})",
    )
    parser.add_argument(
        "--profiles-path",
        type=Path,
        default=DEFAULT_PROFILES_PATH,
        help="Caminho do JSON de perfis etiquetados",
    )
    args = parser.parse_args(argv)

    data = load_profiles(args.profiles_path)
    if args.profile:
        ids = {p["id"] for p in data["profiles"]}
        if args.profile not in ids:
            print(f"Perfil desconhecido: {args.profile}", file=sys.stderr)
            return 2
        data = {
            **data,
            "profiles": [p for p in data["profiles"] if p["id"] == args.profile],
        }

    metrics = compute_metrics(data, profiles_path=args.profiles_path)
    results = _build_results(metrics)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    _print_results(results, verbose=args.verbose, failures_only=args.failures_only)

    if results["label_mismatches"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
