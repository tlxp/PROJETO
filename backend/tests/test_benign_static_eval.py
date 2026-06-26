# --- Módulo: test_benign_static_eval ---
# Testes do corpus benigno (skip se dist/ não existir).

import json
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
DIST = REPO_ROOT / "benign-samples" / "dist"
MANIFEST = BACKEND_ROOT / "evaluation" / "benign_samples_manifest.json"


def _dist_available() -> bool:
    return DIST.is_dir() and any(DIST.glob("*.exe"))


@pytest.mark.skipif(not _dist_available(), reason="benign-samples/dist não compilado")
def test_benign_corpus_no_alto_critico():
    from scripts.run_benign_static_eval import run_evaluation

    metrics = run_evaluation(DIST)
    assert metrics["n_evaluated"] >= 5
    assert metrics["false_positives"] == 0, json.dumps(metrics["samples"], indent=2)


def test_benign_manifest_lists_all_ids():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    ids = {s["id"] for s in data["samples"]}
    assert "BenignHello" in ids
    assert "BenignVmTest" in ids
