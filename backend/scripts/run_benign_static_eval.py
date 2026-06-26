# --- Módulo: run_benign_static_eval.py ---
# Avaliação estática de binários benignos (corpus benign-samples/dist). Sem execução.

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

import config  # noqa: E402
from modules.deobfuscator import Deobfuscator  # noqa: E402
from modules.risk_scorer import RiskScorer  # noqa: E402
from modules.static_analyzer import StaticAnalyzer  # noqa: E402
from modules.yara_scanner import YaraScanner  # noqa: E402

MANIFEST_PATH = BACKEND_ROOT / "evaluation" / "benign_samples_manifest.json"
DEFAULT_DIST = REPO_ROOT / "benign-samples" / "dist"
OUTPUT_PATH = BACKEND_ROOT / "evaluation" / "benign_static_metrics.json"
POSITIVE_LEVELS = frozenset({"ALTO", "CRÍTICO"})


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def _load_manifest() -> dict:
    with MANIFEST_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def _analyze_static_pe(path: Path) -> dict:
    static = StaticAnalyzer().analyze(str(path))
    yara = YaraScanner(rules_dir=str(config.YARA_RULES_DIR)).scan(str(path))
    deobf = Deobfuscator().deobfuscate(str(path))
    file_sha256 = _sha256_file(path)
    risk = RiskScorer().calculate_risk(static, yara, deobf, file_sha256=file_sha256)
    return {
        "path": str(path),
        "sha256": file_sha256,
        "score": risk["score"],
        "level": risk["level"],
        "validation_sample": bool(risk.get("validation_sample")),
        "yara_rules": [m.get("rule") for m in yara if isinstance(m, dict)],
        "suspicious_imports": static.get("suspicious_imports", [])[:8],
        "c2_strings": static.get("c2_strings", [])[:5],
    }


def _predict_malicious(level: str) -> bool:
    return level in POSITIVE_LEVELS


def run_evaluation(dist_dir: Path) -> dict:
    manifest = _load_manifest()
    id_by_name = {s["id"]: s for s in manifest.get("samples", [])}
    rows: list[dict] = []
    missing: list[str] = []

    for sample_id, meta in id_by_name.items():
        exe = dist_dir / f"{sample_id}.exe"
        if not exe.is_file():
            missing.append(sample_id)
            continue
        analysis = _analyze_static_pe(exe)
        predicted = _predict_malicious(analysis["level"])
        rows.append(
            {
                "id": sample_id,
                "label": "benign",
                "note": meta.get("note", ""),
                "subdir": meta.get("subdir", ""),
                **analysis,
                "predicted_malicious": predicted,
                "false_positive": predicted,
            }
        )

    # Extras na pasta dist não listados no manifesto
    for path in sorted(dist_dir.glob("*.exe")):
        if path.stem in id_by_name:
            continue
        analysis = _analyze_static_pe(path)
        predicted = _predict_malicious(analysis["level"])
        rows.append(
            {
                "id": path.stem,
                "label": "benign",
                "note": "unlisted",
                **analysis,
                "predicted_malicious": predicted,
                "false_positive": predicted,
            }
        )

    fp = sum(1 for r in rows if r["false_positive"])
    tn = len(rows) - fp
    specificity = tn / len(rows) if rows else 0.0

    return {
        "methodology": (
            "Static analysis only on benign corpus (benign-samples/dist). "
            "Success = no sample classified ALTO/CRITICO (true negatives). "
            "Specificity = TN / (TN + FP)."
        ),
        "dist_dir": str(dist_dir),
        "n_evaluated": len(rows),
        "n_expected": len(id_by_name),
        "missing_exes": missing,
        "false_positives": fp,
        "true_negatives": tn,
        "specificity": round(specificity, 3),
        "all_passed": fp == 0 and len(missing) == 0,
        "samples": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Avaliação estática do corpus benigno")
    parser.add_argument(
        "--dist-dir",
        type=Path,
        default=Path(os.environ.get("BENIGN_SAMPLES_DIST", str(DEFAULT_DIST))),
    )
    args = parser.parse_args()
    dist_dir: Path = args.dist_dir

    if not dist_dir.is_dir() or not list(dist_dir.glob("*.exe")):
        print(
            f"Sem .exe em {dist_dir}. Execute: .\\benign-samples\\build.ps1",
            file=sys.stderr,
        )
        return 2

    metrics = run_evaluation(dist_dir)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2, ensure_ascii=False)

    print(json.dumps(metrics, indent=2, ensure_ascii=False))
    if metrics["false_positives"]:
        print(f"\nAviso: {metrics['false_positives']} falso(s) positivo(s).", file=sys.stderr)
    if metrics["missing_exes"]:
        print(f"\nAviso: em falta {metrics['missing_exes']}", file=sys.stderr)
    return 0 if metrics["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
