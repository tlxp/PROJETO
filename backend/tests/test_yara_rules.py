# --- Módulo: test_yara_rules ---
# Testes de compilação das regras YARA (requer yara-python).

from pathlib import Path

import pytest

try:
    import yara
except ImportError:
    yara = None

RULES_DIR = Path(__file__).resolve().parents[2] / "yara_rules"


@pytest.mark.skipif(yara is None, reason="yara-python não instalado")
# --- Testes de YaraRulesCompile ---
class TestYaraRulesCompile:
    def test_todas_as_regras_compilam(self):
        rule_files = {str(p): str(p) for p in RULES_DIR.glob("*.yar")}
        assert len(rule_files) >= 4, "Esperadas pelo menos 4 ficheiros .yar"
        compiled = yara.compile(filepaths=rule_files)
        assert compiled is not None

    def test_regras_tem_meta_version(self):
        for path in RULES_DIR.glob("*.yar"):
            text = path.read_text(encoding="utf-8")
            assert "version = " in text, f"{path.name} deve incluir meta version"
            assert "pe.is_pe" in text, f"{path.name} deve restringir a PE"
            assert "filesize <" in text, f"{path.name} deve limitar filesize"
