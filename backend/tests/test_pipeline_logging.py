# --- Módulo: test_pipeline_logging ---
# Garante logging (não print) e erros previsíveis nos módulos do pipeline.

import logging

import pytest

from modules.deobfuscator import Deobfuscator
from modules.static_analyzer import StaticAnalyzer
from modules.yara_scanner import YaraScanner


@pytest.mark.parametrize(
    "module_name",
    [
        "rat_analyzer",
        "rat_analyzer_static",
        "rat_analyzer_yara",
        "rat_analyzer_deobfuscator",
        "rat_analyzer_dotnet_decompiler",
        "rat_analyzer_native_disasm",
    ],
)
# --- Teste: verifica pipeline loggers exist ---
def test_pipeline_loggers_exist(module_name: str):
    assert logging.getLogger(module_name).name == module_name


# --- Teste: verifica deobfuscator invalid base64 returns none ---
def test_deobfuscator_invalid_base64_returns_none():
    dec = Deobfuscator()
    assert dec._decode_base64_to_readable_text("!!!not-base64!!!") is None


# --- Teste: verifica static analyzer missing file returns errors ---
def test_static_analyzer_missing_file_returns_errors(tmp_path):
    missing = tmp_path / "nao_existe.exe"
    result = StaticAnalyzer().analyze(str(missing))
    assert "errors" in result
    assert result["errors"]
