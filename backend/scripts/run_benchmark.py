#!/usr/bin/env python3
# --- Módulo: run_benchmark ---
# Benchmark estático reprodutível; captura opcional de tempos dinâmicos.

from __future__ import annotations

import json
import os
import statistics
import sys
import time
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from rat_analyzer import RATAnalyzer  # noqa: E402

OUTPUT_PATH = BACKEND_ROOT / "evaluation" / "benchmark_results.json"
DEFAULT_SAMPLE = REPO_ROOT / "wpf-gui" / "bin" / "Release" / "net8.0-windows" / "Rat Analyzer.exe"


# --- Percentil interpolado de uma lista ordenada ---
def _percentile(sorted_values: list[float], p: float) -> float:
    if not sorted_values:
        return 0.0
    k = (len(sorted_values) - 1) * p
    f = int(k)
    c = min(f + 1, len(sorted_values) - 1)
    if f == c:
        return sorted_values[f]
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


# --- Estatísticas descritivas dos tempos de execução ---
def _summarize_times(times: list[float]) -> dict:
    ordered = sorted(times)
    return {
        "n": len(times),
        "median_s": round(statistics.median(times), 1),
        "mean_s": round(statistics.mean(times), 1),
        "min_s": round(min(times), 1),
        "max_s": round(max(times), 1),
        "iqr_s": round(_percentile(ordered, 0.75) - _percentile(ordered, 0.25), 1),
        "all_s": [round(t, 1) for t in times],
    }


# --- Benchmark do pipeline estático (N execuções) ---
def run_static_benchmark(sample: Path, runs: int) -> dict:
    if not sample.is_file():
        raise FileNotFoundError(f"Sample not found: {sample}")
    times: list[float] = []
    for _ in range(runs):
        t0 = time.perf_counter()
        analyzer = RATAnalyzer(str(sample))
        analyzer.analyze()
        times.append(time.perf_counter() - t0)
    return {
        "sample": str(sample),
        "sample_size_bytes": sample.stat().st_size,
        **_summarize_times(times),
    }


# --- Ponto de entrada: grava benchmark_results.json ---
def main() -> int:
    runs = int(os.environ.get("BENCHMARK_STATIC_RUNS", "5"))
    sample = Path(os.environ.get("BENCHMARK_SAMPLE", str(DEFAULT_SAMPLE)))

    result: dict = {
        "static_pipeline": run_static_benchmark(sample, runs),
        "dynamic": {},
    }

    dynamic_json = os.environ.get("BENCHMARK_DYNAMIC_JSON")
    if dynamic_json:
        path = Path(dynamic_json)
        with path.open(encoding="utf-8") as f:
            result["dynamic"] = json.load(f)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
