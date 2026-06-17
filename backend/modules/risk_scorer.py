"""
Módulo de Scoring de Risco
Calcula score de risco baseado em múltiplos fatores
"""

from typing import Dict, List, Optional

# SHA256 de amostras inofensivas para validação do pipeline (alinhado com benign_validation_hashes.txt na VM).
BENIGN_VALIDATION_SHA256 = frozenset({
    "9CB316156CA52F30F322B347CA78C46B2DE29CE1DF3204A5AF8F8914359995C8",  # BenignVmTest.exe
})


class RiskScorer:
    """Calcula score de risco de 0-100 baseado na análise"""

    WEIGHTS = {
        "suspicious_imports": 12,
        "suspicious_functions": 20,
        "c2_strings": 20,
        "stealer_indicators": 15,
        "persistence_indicators": 10,
        "evasion_techniques": 12,
        "yara_matches": 25,
        "packer_indicators": 10,
        "obfuscation": 8,
        "high_entropy": 5,
    }

    def __init__(self):
        pass

    def calculate_risk(
        self,
        static_analysis: Dict,
        yara_matches: List[Dict],
        deobfuscation: Dict,
        file_sha256: Optional[str] = None,
    ) -> Dict:
        """Calcula score de risco total com retornos decrescentes e nível calibrado."""
        score = 0
        details: Dict = {}

        suspicious_imports = len(static_analysis.get("suspicious_imports", []))
        import_score = self._tier_score(suspicious_imports, per_item=4, maximum=self.WEIGHTS["suspicious_imports"])
        score += import_score
        details["suspicious_imports"] = {
            "count": suspicious_imports,
            "score": import_score,
            "max": self.WEIGHTS["suspicious_imports"],
        }

        suspicious_functions = len(static_analysis.get("suspicious_functions", []))
        function_score = self._tier_score(
            suspicious_functions, per_item=6, maximum=self.WEIGHTS["suspicious_functions"]
        )
        score += function_score
        details["suspicious_functions"] = {
            "count": suspicious_functions,
            "score": function_score,
            "max": self.WEIGHTS["suspicious_functions"],
        }

        c2_strings = len(static_analysis.get("c2_strings", []))
        c2_score = self._score_c2_strings(c2_strings)
        score += c2_score
        details["c2_strings"] = {
            "count": c2_strings,
            "score": c2_score,
            "max": self.WEIGHTS["c2_strings"],
        }

        stealer = len(static_analysis.get("stealer_indicators", []))
        stealer_score = self._tier_score(stealer, per_item=4, maximum=self.WEIGHTS["stealer_indicators"])
        score += stealer_score
        details["stealer_indicators"] = {
            "count": stealer,
            "score": stealer_score,
            "max": self.WEIGHTS["stealer_indicators"],
        }

        persistence = len(static_analysis.get("persistence_indicators", []))
        persistence_score = self._tier_score(
            persistence, per_item=3, maximum=self.WEIGHTS["persistence_indicators"]
        )
        score += persistence_score
        details["persistence_indicators"] = {
            "count": persistence,
            "score": persistence_score,
            "max": self.WEIGHTS["persistence_indicators"],
        }

        evasion_techniques = len(static_analysis.get("evasion_techniques", []))
        evasion_score = self._tier_score(
            evasion_techniques, per_item=3, maximum=self.WEIGHTS["evasion_techniques"]
        )
        score += evasion_score
        details["evasion_techniques"] = {
            "count": evasion_techniques,
            "score": evasion_score,
            "max": self.WEIGHTS["evasion_techniques"],
        }

        yara_count = len(yara_matches)
        yara_score = self._tier_score(yara_count, per_item=12, maximum=self.WEIGHTS["yara_matches"])
        score += yara_score
        details["yara_matches"] = {
            "count": yara_count,
            "score": yara_score,
            "max": self.WEIGHTS["yara_matches"],
        }

        packer_indicators = len(static_analysis.get("packer_indicators", []))
        packer_score = self._tier_score(
            packer_indicators, per_item=4, maximum=self.WEIGHTS["packer_indicators"]
        )
        score += packer_score
        details["packer_indicators"] = {
            "count": packer_indicators,
            "score": packer_score,
            "max": self.WEIGHTS["packer_indicators"],
        }

        obfuscation_indicators = len(deobfuscation.get("obfuscation_indicators", []))
        obfuscation_score = self._tier_score(
            obfuscation_indicators, per_item=2, maximum=self.WEIGHTS["obfuscation"]
        )
        score += obfuscation_score
        details["obfuscation"] = {
            "count": obfuscation_indicators,
            "score": obfuscation_score,
            "max": self.WEIGHTS["obfuscation"],
        }

        entropy_data = static_analysis.get("entropy", {})
        high_entropy_count = sum(1 for e in entropy_data.values() if e > 7.0)
        entropy_score = self._tier_score(
            high_entropy_count, per_item=2, maximum=self.WEIGHTS["high_entropy"]
        )
        score += entropy_score
        details["high_entropy"] = {
            "count": high_entropy_count,
            "score": entropy_score,
            "max": self.WEIGHTS["high_entropy"],
        }

        score = min(max(score, 0), 100)
        level = self._get_risk_level(score, details, yara_count)

        result: Dict = {
            "score": score,
            "level": level,
            "details": details,
        }
        sha = (file_sha256 or "").strip().upper()
        if sha and sha in BENIGN_VALIDATION_SHA256:
            result["validation_sample"] = True
            result["validation_note"] = (
                "Amostra de validação conhecida (BenignVmTest). Compare sempre com a "
                "análise comportamental na VM para o veredicto final."
            )
        return result

    @staticmethod
    def _tier_score(count: int, per_item: int, maximum: int) -> int:
        if count <= 0:
            return 0
        return min(count * per_item, maximum)

    @staticmethod
    def _score_c2_strings(count: int) -> int:
        """C2: primeiros indicadores pesam mais; evita saturar só com ruído de strings."""
        if count <= 0:
            return 0
        if count == 1:
            return 4
        if count == 2:
            return 8
        if count <= 5:
            return 12
        return min(12 + (count - 5) * 2, 20)

    def _get_risk_level(self, score: int, details: Dict, yara_count: int) -> str:
        """Nível calibrado: ALTO/CRÍTICO exigem sinais fortes, não só ruído heurístico."""
        has_yara = yara_count > 0
        strong_c2 = details["c2_strings"]["count"] >= 2
        strong_funcs = details["suspicious_functions"]["count"] >= 2
        network_imports = details["suspicious_imports"]["count"] >= 1
        stealer_or_persist = (
            details["stealer_indicators"]["count"] >= 1
            and details["persistence_indicators"]["count"] >= 1
        )

        strong_evidence = has_yara or (
            strong_c2 and (strong_funcs or network_imports)
        ) or (strong_funcs and network_imports and stealer_or_persist)

        if score >= 72 and strong_evidence:
            return "CRÍTICO"
        if score >= 48 and (has_yara or strong_c2 or (strong_funcs and network_imports)):
            return "ALTO"
        if score >= 35:
            return "MÉDIO"
        if score >= 15:
            return "BAIXO"
        return "MUITO BAIXO"
