"""
Testes unitários para o módulo obfuscation_snippet_extractor.
Executar: python -m unittest backend.tests.test_obfuscation_snippet_extractor
Ou a partir de backend: python -m unittest tests.test_obfuscation_snippet_extractor
"""

import sys
import tempfile
import unittest
from pathlib import Path

# Garantir que backend está no path
_BACKEND = Path(__file__).resolve().parent.parent
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from modules.obfuscation_snippet_extractor import (
    ObfuscationSnippet,
    build_snippets_summary,
    detect_obfuscation_with_positions,
    write_obfuscated_snippets_file,
    write_deobfuscated_snippets_file,
)


class TestDetectObfuscation(unittest.TestCase):
    def test_base64_and_concatenation(self):
        """Deteta Base64 literal e concatenação C# e devolve snippets com posição."""
        content = """
using System;
class Program {
    void Foo() {
        string a = "x" + "y";
        string b = "aHR0cDovL2V4YW1wbGUuY29tLzEyMzQ=";
    }
}
"""
        snippets = detect_obfuscation_with_positions(content, source_path="test.cs")
        self.assertGreaterEqual(len(snippets), 1)
        for s in snippets:
            self.assertIsInstance(s, ObfuscationSnippet)
            self.assertGreaterEqual(s.line_start, 1)
            self.assertGreaterEqual(s.line_end, s.line_start)
            self.assertGreater(len(s.snippet), 0)
            self.assertTrue(s.description)

    def test_convert_frombase64(self):
        """Deteta Convert.FromBase64String no código."""
        content = """
    var data = Convert.FromBase64String(encoded);
"""
        snippets = detect_obfuscation_with_positions(content, source_path="x.cs")
        self.assertTrue(
            any("Base64" in s.description or "FromBase64String" in s.description for s in snippets)
        )


class TestBuildSummary(unittest.TestCase):
    def test_summary_by_description(self):
        """Resumo agrupa por descrição."""
        snippets = [
            ObfuscationSnippet("obf", "Base64 literal", 1, 3, "code", "f.cs"),
            ObfuscationSnippet("obf", "Base64 literal", 5, 7, "code2", "f.cs"),
            ObfuscationSnippet("obf", "C# string concatenation", 2, 4, "code3", "f.cs"),
        ]
        summary = build_snippets_summary(snippets)
        self.assertEqual(summary["Base64 literal"], 2)
        self.assertEqual(summary["C# string concatenation"], 1)


class TestWriteSnippetFiles(unittest.TestCase):
    def test_write_obfuscated_snippets_file(self):
        """Escreve ficheiro de trechos obfuscados com secções esperadas."""
        snippets = [
            ObfuscationSnippet("obf", "Test type", 1, 2, "line1\nline2", "source.cs"),
        ]
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "obf.txt"
            write_obfuscated_snippets_file(snippets, out)
            self.assertTrue(out.exists())
            text = out.read_text(encoding="utf-8")
            self.assertIn("--- snippet 1 ---", text)
            self.assertIn("Test type", text)
            self.assertIn("line1", text)
            self.assertIn("source.cs", text)

    def test_write_deobfuscated_snippets_file(self):
        """Escreve ficheiro de trechos deobfuscados aplicando função."""
        snippets = [
            ObfuscationSnippet("obf", "Test", 1, 2, "original", "s.cs"),
        ]

        def deob(s: str) -> str:
            return s + "\n  // deobfuscated"

        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "deob.txt"
            write_deobfuscated_snippets_file(snippets, out, deob)
            self.assertTrue(out.exists())
            text = out.read_text(encoding="utf-8")
            self.assertIn("--- snippet 1 ---", text)
            self.assertIn("original", text)
            self.assertIn("deobfuscated", text)


if __name__ == "__main__":
    unittest.main()
