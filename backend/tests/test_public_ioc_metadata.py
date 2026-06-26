# --- Módulo: test_public_ioc_metadata ---
# Valida metadados públicos (MalwareBazaar) usados na avaliação do relatório.

import json
from pathlib import Path

from modules.risk_scorer import BENIGN_VALIDATION_SHA256, RiskScorer

_METADATA_PATH = Path(__file__).resolve().parents[1] / "evaluation" / "public_ioc_metadata.json"


def _load_metadata() -> dict:
    with _METADATA_PATH.open(encoding="utf-8") as f:
        return json.load(f)


class TestPublicIocMetadata:
    def test_metadata_file_has_required_fields(self):
        data = _load_metadata()
        assert data["source"]
        assert isinstance(data["samples"], list)
        assert len(data["samples"]) >= 6
        for entry in data["samples"]:
            assert len(entry["sha256"]) == 64
            assert entry["family"]
            assert isinstance(entry["tags"], list)

    def test_benign_hash_not_listed_as_malware_family(self):
        benign = next(iter(BENIGN_VALIDATION_SHA256))
        data = _load_metadata()
        malicious = [
            s
            for s in data["samples"]
            if s["family"] not in {"BenignVmTest", "unknown"}
        ]
        malicious_hashes = {s["sha256"].upper() for s in malicious}
        assert benign not in malicious_hashes

    def test_benign_validation_hash_annotated(self):
        benign = next(iter(BENIGN_VALIDATION_SHA256))
        result = RiskScorer().calculate_risk({}, [], {"obfuscation_indicators": []}, file_sha256=benign)
        assert result.get("validation_sample") is True

    def test_synthetic_rat_profile_matches_public_family_expectation(self):
        # Perfil sintético alinhado com indicadores típicos de famílias RAT públicas (Quasar/AsyncRAT).
        static = {
            "suspicious_imports": ["wininet.dll", "ws2_32.dll"],
            "suspicious_functions": ["CreateRemoteThread", "WriteProcessMemory"],
            "c2_strings": ["http://203.0.113.9:8080/beacon", "http://evil.c2.example/api/collect"],
            "stealer_indicators": ["Chrome\\User Data"],
            "persistence_indicators": ["CurrentVersion\\Run\\"],
            "evasion_techniques": ["CheckRemoteDebuggerPresent"],
            "entropy": {},
            "packer_indicators": [],
        }
        yara = [{"rule": "RAT_Generic"}]
        result = RiskScorer().calculate_risk(static, yara, {"obfuscation_indicators": []})
        assert result["score"] >= 48
        assert result["level"] in {"ALTO", "CRÍTICO"}
