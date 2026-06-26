# --- Módulo: test_api ---
# Testes da API FastAPI com TestClient (RATAnalyzer substituído por fake).

import uuid

import pytest
from fastapi.testclient import TestClient

import api


@pytest.fixture()
# --- Fixture: cliente HTTP de teste ---
def client():
    return TestClient(api.app)


# --- Fake RATAnalyzer para testes (sem YARA/Ghidra/ILSpy) ---
class FakeAnalyzer:

    # --- Guarda caminho do alvo sem inicializar pipeline real ---
    def __init__(self, target_file, output_dir=None, use_dotnet_decompiler=False, log_callback=None, **kwargs):
        self.target_file = target_file

    # --- Devolve resultado fixo de risco baixo ---
    def analyze(self):
        return {"risk_score": 7, "risk_level": "LOW"}


@pytest.fixture()
# --- Fixture: pipeline com RATAnalyzer fake ---
def fake_pipeline(monkeypatch):
    monkeypatch.setattr("routers.analyze.RATAnalyzer", FakeAnalyzer)


# --- Testes de AnalyzeUpload ---
class TestAnalyzeUpload:
    def test_upload_valido(self, client, fake_pipeline):
        r = client.post(
            "/api/analyze",
            files={"file": ("sample.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 200
        body = r.json()
        assert body["fileName"] == "sample.exe"
        assert body["riskScore"] == 7

    def test_filename_malicioso_rejeitado(self, client, fake_pipeline):
        r = client.post(
            "/api/analyze",
            files={"file": ("..\\..\\x.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 400

    def test_filename_traversal_posix_rejeitado(self, client, fake_pipeline):
        r = client.post(
            "/api/analyze",
            files={"file": ("../../x.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 400

    def test_extensao_nao_suportada(self, client, fake_pipeline):
        r = client.post(
            "/api/analyze",
            files={"file": ("notes.txt", b"hello", "text/plain")},
        )
        assert r.status_code == 400

    def test_limite_de_tamanho_413(self, client, fake_pipeline, monkeypatch):
        monkeypatch.setenv("RATANALYZER_MAX_UPLOAD_MB", "1")
        payload = b"A" * (2 * 1024 * 1024)  # 2 MB > limite de 1 MB
        r = client.post(
            "/api/analyze",
            files={"file": ("big.exe", payload, "application/octet-stream")},
        )
        assert r.status_code == 413

    def test_submit_analysis_filename_malicioso(self, client, fake_pipeline):
        r = client.post(
            "/api/analysis",
            files={"file": ("..\\..\\x.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 400

    def test_submit_analysis_limite_de_tamanho(self, client, fake_pipeline, monkeypatch):
        monkeypatch.setenv("RATANALYZER_MAX_UPLOAD_MB", "1")
        payload = b"B" * (2 * 1024 * 1024)
        r = client.post(
            "/api/analysis",
            files={"file": ("big.exe", payload, "application/octet-stream")},
        )
        assert r.status_code == 413


# --- Testes de JobIdValidation ---
class TestJobIdValidation:
    def test_job_id_invalido_devolve_400(self, client):
        r = client.get("/api/analysis/not-a-uuid")
        assert r.status_code == 400

    def test_job_id_traversal_devolve_400(self, client):
        r = client.get("/api/analysis/..%5C..%5Csecret")
        assert r.status_code in (400, 404)

    def test_job_id_valido_inexistente_devolve_404(self, client):
        r = client.get(f"/api/analysis/{uuid.uuid4()}")
        assert r.status_code == 404

    def test_artifacts_job_id_invalido_devolve_400(self, client):
        r = client.get("/api/analysis/zzz/artifacts/obfuscated_snippets")
        assert r.status_code == 400


# --- Testes de ApiToken ---
class TestApiToken:
    def test_sem_env_token_nao_exige_header(self, client, monkeypatch):
        monkeypatch.delenv("RATANALYZER_API_TOKEN", raising=False)
        r = client.post("/api/storage/cleanup", json={})
        assert r.status_code == 200

    def test_com_env_token_exige_header(self, client, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post("/api/storage/cleanup", json={})
        assert r.status_code == 401

    def test_token_errado_rejeitado(self, client, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post("/api/storage/cleanup", json={}, headers={"X-API-Token": "errado"})
        assert r.status_code == 401

    def test_token_correto_aceite(self, client, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post("/api/storage/cleanup", json={}, headers={"X-API-Token": "super-secreto"})
        assert r.status_code == 200

    def test_purge_protegido(self, client, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post("/api/storage/purge")
        assert r.status_code == 401

    def test_analyze_exige_token_quando_configurado(self, client, fake_pipeline, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post(
            "/api/analyze",
            files={"file": ("sample.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 401

    def test_analyze_aceita_com_token(self, client, fake_pipeline, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post(
            "/api/analyze",
            files={"file": ("sample.exe", b"MZfakebinary", "application/octet-stream")},
            headers={"X-API-Token": "super-secreto"},
        )
        assert r.status_code == 200

    def test_submit_analysis_exige_token(self, client, fake_pipeline, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "super-secreto")
        r = client.post(
            "/api/analysis",
            files={"file": ("sample.exe", b"MZfakebinary", "application/octet-stream")},
        )
        assert r.status_code == 401


# --- Testes de ListAnalyses ---
class TestListAnalyses:
    def test_limit_com_teto(self, client):
        r = client.get("/api/analyses", params={"limit": 9999})
        assert r.status_code == 200
        assert r.json()["limit"] == 200
