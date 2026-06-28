# --- Módulo: test_risk_scoring ---
# Testes do scoring estático e heurísticas do StaticAnalyzer.

from modules.risk_scorer import BENIGN_VALIDATION_SHA256, RiskScorer
from modules.static_analyzer import StaticAnalyzer


# --- Testes de StaticAnalyzerFilters ---
class TestStaticAnalyzerFilters:
    def test_rejeita_urls_microsoft_como_c2(self):
        sa = StaticAnalyzer()
        assert sa._is_false_positive_c2("https://aka.ms/dotnet-warnings/{0}")
        assert sa._is_false_positive_c2("http://www.microsoft.com/pkiops/Docs/Repository.htm")
        assert not sa._is_high_confidence_url("https://aka.ms/dotnet-warnings/{0}")

    def test_rejeita_tipos_dotnet_c2(self):
        sa = StaticAnalyzer()
        assert sa._is_false_positive_c2("c2.VoteRequestDone")
        assert sa._is_false_positive_c2("c2.Aborted")

    def test_aceita_ip_porta_como_c2(self):
        sa = StaticAnalyzer()
        assert sa._is_high_confidence_url("http://203.0.113.50:4444/")

    def test_persistencia_exige_caminho_run(self):
        sa = StaticAnalyzer()
        text = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce\\RATAnalyzerBenignFlag"
        found = []
        for ind in sa.PERSISTENCE_INDICATORS:
            if ind.lower() in text.lower():
                found.append(ind)
        assert found


# --- Testes de RiskScorer ---
class TestRiskScorer:
# --- Resultado de deobfuscação vazio para testes ---
    def _empty_deobf(self):
        return {"obfuscation_indicators": []}

    def test_perfil_benignvmtest_nao_atinge_alto(self):
        # *Perfil típico pós-afinação: poucos sinais fortes, sem YARA*
        static = {
            "suspicious_imports": [],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": [],
            "persistence_indicators": ["CurrentVersion\\RunOnce\\"],
            "evasion_techniques": [],
            "entropy": {".text": 6.4},
            "packer_indicators": [],
        }
        deobf = {"obfuscation_indicators": ["String concatenation obfuscation"] * 2}
        result = RiskScorer().calculate_risk(static, [], deobf)
        assert result["score"] < 48
        assert result["level"] in {"MUITO BAIXO", "BAIXO", "MÉDIO"}

    def test_perfil_ruido_heuristico_nao_conta_como_alto(self):
        # *Contagens inflacionadas não bastam para ALTO sem sinais fortes*
        static = {
            "suspicious_imports": [],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": [],
            "persistence_indicators": ["RegSetValueEx"],
            "evasion_techniques": ["GetTickCount", "IsDebuggerPresent", "OutputDebugString"],
            "entropy": {},
            "packer_indicators": [],
        }
        deobf = {"obfuscation_indicators": ["x", "y"]}
        result = RiskScorer().calculate_risk(static, [], deobf)
        assert result["level"] != "ALTO"
        assert result["level"] != "CRÍTICO"

    def test_rat_com_yara_e_c2_atinge_alto(self):
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
        result = RiskScorer().calculate_risk(static, yara, self._empty_deobf())
        assert result["score"] >= 48
        assert result["level"] in {"ALTO", "CRÍTICO"}

    def test_benign_validation_hash_anota_resultado(self):
        sha = next(iter(BENIGN_VALIDATION_SHA256))
        result = RiskScorer().calculate_risk({}, [], self._empty_deobf(), file_sha256=sha)
        assert result.get("validation_sample") is True
        assert "BenignVmTest" in result.get("validation_note", "")

    def test_c2_score_decrescente(self):
        scorer = RiskScorer()
        assert scorer._score_c2_strings(1) < scorer._score_c2_strings(5)
        assert scorer._score_c2_strings(50) == 20

    def test_yara_isolado_nao_atinge_alto(self):
        result = RiskScorer().calculate_risk({}, [{"rule": "RAT_Generic"}], self._empty_deobf())
        assert result["score"] < 48
        assert result["level"] not in {"ALTO", "CRÍTICO"}

    def test_yara_fp_noise_permanece_baixo(self):
        static = {
            "suspicious_imports": [],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": [],
            "persistence_indicators": [],
            "evasion_techniques": ["GetTickCount"],
            "entropy": {},
            "packer_indicators": [],
        }
        yara = [{"rule": "suspicious_generic"}]
        deobf = {
            "obfuscation_indicators": [
                "String concatenation obfuscation",
                "Base64 encoded strings",
            ]
        }
        result = RiskScorer().calculate_risk(static, yara, deobf)
        assert result["level"] == "BAIXO"

    def test_stealer_persist_yara_atinge_alto_com_score_35(self):
        static = {
            "suspicious_imports": [],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": ["Chrome\\User Data", "Login Data", "Cookies"],
            "persistence_indicators": ["CurrentVersion\\Run\\", "RunOnce"],
            "evasion_techniques": ["IsDebuggerPresent", "CheckRemoteDebuggerPresent"],
            "entropy": {".text": 7.2},
            "packer_indicators": ["UPX"],
        }
        yara = [{"rule": "Stealer_Generic"}]
        deobf = {"obfuscation_indicators": ["Base64 encoded strings"]}
        result = RiskScorer().calculate_risk(static, yara, deobf)
        assert result["score"] >= 35
        assert result["level"] in {"ALTO", "CRÍTICO"}

    def test_ruido_heuristico_teto_medio(self):
        static = {
            "suspicious_imports": [],
            "suspicious_functions": ["VirtualAlloc"],
            "c2_strings": ["http://noise.example/"],
            "stealer_indicators": ["a", "b", "c", "d"],
            "persistence_indicators": ["a", "b", "c"],
            "evasion_techniques": ["a", "b", "c", "d"],
            "entropy": {".text": 7.5, ".data": 7.2},
            "packer_indicators": ["UPX", "ASPack"],
        }
        deobf = {"obfuscation_indicators": ["a", "b", "c", "d"]}
        result = RiskScorer().calculate_risk(static, [], deobf)
        assert result["score"] >= 35
        assert result["level"] == "MÉDIO"

    def test_benign_http_client_nao_atinge_medio(self):
        static = {
            "suspicious_imports": ["wininet.dll", "ws2_32.dll"],
            "suspicious_functions": [],
            "c2_strings": [],
            "stealer_indicators": [],
            "persistence_indicators": [],
            "evasion_techniques": [],
            "entropy": {},
            "packer_indicators": [],
        }
        result = RiskScorer().calculate_risk(static, [], self._empty_deobf())
        assert result["level"] in {"MUITO BAIXO", "BAIXO"}

    def test_c2_unico_com_rede_nao_atinge_alto_sem_score(self):
        static = {
            "suspicious_imports": ["wininet.dll", "ws2_32.dll"],
            "suspicious_functions": ["CreateRemoteThread", "WriteProcessMemory"],
            "c2_strings": ["http://203.0.113.50:4444/"],
            "stealer_indicators": ["Chrome"],
            "persistence_indicators": ["Run"],
            "evasion_techniques": ["IsDebuggerPresent"],
            "entropy": {},
            "packer_indicators": [],
        }
        result = RiskScorer().calculate_risk(static, [], self._empty_deobf())
        assert result["score"] < 48
        assert result["level"] not in {"ALTO", "CRÍTICO"}

    def test_fronteira_critico_score_71_vs_72(self):
        scorer = RiskScorer()
        base = {
            "suspicious_imports": ["wininet.dll", "ws2_32.dll"],
            "suspicious_functions": ["CreateRemoteThread", "WriteProcessMemory"],
            "c2_strings": ["http://a", "http://b"],
            "stealer_indicators": ["Chrome"],
            "persistence_indicators": ["Run"],
            "entropy": {},
            "packer_indicators": [],
        }
        deobf = {"obfuscation_indicators": ["x", "y"]}
        alto = scorer.calculate_risk(
            {**base, "evasion_techniques": ["IsDebuggerPresent"] * 2, "packer_indicators": []},
            [{"rule": "RAT_Generic"}, {"rule": "evasion"}],
            deobf,
        )
        critico = scorer.calculate_risk(
            {**base, "evasion_techniques": ["IsDebuggerPresent"] * 3, "packer_indicators": []},
            [{"rule": "RAT_Generic"}, {"rule": "evasion"}],
            deobf,
        )
        assert alto["score"] == 69
        assert alto["level"] == "ALTO"
        assert critico["score"] == 72
        assert critico["level"] == "CRÍTICO"
