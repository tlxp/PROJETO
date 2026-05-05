from __future__ import annotations

import hashlib
from pathlib import Path

import config


APP_VERSION = "1.0.0"


def _sha256_text(s: str) -> str:
    h = hashlib.sha256()
    h.update(s.encode("utf-8", "ignore"))
    return h.hexdigest()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_pipeline_version() -> str:
    """
    Versão do pipeline para efeitos de cache/deduplicação.

    Deve mudar quando:
      - regras YARA mudam
      - lógica de análise muda (APP_VERSION)
      - flags que alteram artefactos mudam
    """
    yara_dir = Path(config.YARA_RULES_DIR)
    yara_hashes: list[str] = []
    if yara_dir.exists():
        for p in sorted(yara_dir.glob("*.yar")):
            try:
                yara_hashes.append(f"{p.name}:{_sha256_file(p)}")
            except OSError:
                yara_hashes.append(f"{p.name}:<unreadable>")

    flags = {
        "KEEP_ILSPY_TREE": bool(getattr(config, "KEEP_ILSPY_TREE", True)),
        "KEEP_GHIDRA_PROJECT": bool(getattr(config, "KEEP_GHIDRA_PROJECT", True)),
    }

    material = "\n".join(
        [
            f"app_version={APP_VERSION}",
            "yara=" + "|".join(yara_hashes),
            "flags=" + "|".join(f"{k}={int(bool(v))}" for k, v in sorted(flags.items())),
        ]
    )
    return _sha256_text(material)


__all__ = ["compute_pipeline_version", "APP_VERSION"]

