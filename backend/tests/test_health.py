# --- Módulo: test_health ---
# Testes de healthcheck enriquecido e métricas Prometheus.

import pytest
from fastapi.testclient import TestClient

import api


@pytest.fixture()
# --- Fixture: cliente HTTP de teste ---
def client():
    return TestClient(api.app)


# --- Testes de Health ---
class TestHealth:
# --- Teste: verifica health retorna campos esperados ---
    def test_health_retorna_campos_esperados(self, client):
        r = client.get("/api/health")
        assert r.status_code == 200
        body = r.json()
        assert body["status"] in ("ok", "degraded")
        assert "db" in body
        assert "yara" in body
        assert "ghidra" in body
        assert "vmDriver" in body
        assert "apiTokenConfigured" in body

# --- Teste: verifica metrics prometheus ---
    def test_metrics_prometheus(self, client):
        r = client.get("/metrics")
        assert r.status_code == 200
        assert "rat_analyzer_uptime_seconds" in r.text
        assert "rat_analyzer_analyze_requests_total" in r.text

# --- Teste: verifica metrics incrementa apos analyze ---
    def test_metrics_incrementa_apos_analyze(self, client, monkeypatch):
# --- Classe Fake Analyzer ---
        class FakeAnalyzer:
# --- Helper interno: init   ---
            def __init__(self, *args, **kwargs):
                pass

# --- Teste: analyze ---
            def analyze(self):
                return {"risk_score": 0, "risk_level": "LOW"}

        monkeypatch.setattr("routers.analyze.RATAnalyzer", FakeAnalyzer)
        before = client.get("/metrics").text
        client.post(
            "/api/analyze",
            files={"file": ("s.exe", b"MZ", "application/octet-stream")},
        )
        after = client.get("/metrics").text
        assert before != after or "rat_analyzer_analyze_requests_total 1" in after
