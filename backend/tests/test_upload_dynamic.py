# --- Módulo: test_upload_dynamic ---
# Testes do endpoint /api/analysis/upload_dynamic.

import uuid

import pytest
from fastapi.testclient import TestClient

import api


@pytest.fixture()
# --- Fixture: cliente HTTP de teste ---
def client():
    return TestClient(api.app)


# --- Testes de UploadDynamic ---
class TestUploadDynamic:
    def test_cria_job_dinamico_com_relatorio(self, client):
        r = client.post(
            "/api/analysis/upload_dynamic",
            json={
                "fileName": "sample.exe",
                "report": "RELATÓRIO VM\nScore: 42",
                "runId": "20250616_120000",
                "status": "completed",
            },
        )
        assert r.status_code == 200
        body = r.json()
        assert body["analysisType"] == "dynamic"
        assert body["status"] == "completed"
        job_id = body["jobId"]
        assert uuid.UUID(job_id).version == 4

        detail = client.get(f"/api/analysis/{job_id}")
        assert detail.status_code == 200
        payload = detail.json()
        assert payload["dynamicResult"]["dynamicReportText"].startswith("RELATÓRIO VM")

    def test_associa_a_job_estatico_existente(self, client):
        static = client.post(
            "/api/analysis/upload_static",
            json={
                "fileName": "sample.exe",
                "report": "estático",
                "cCode": "void main(){}",
                "ilCode": "IL",
                "riskScore": 10,
                "riskLevel": "LOW",
            },
        )
        assert static.status_code == 200
        job_id = static.json()["jobId"]

        running = client.post(
            "/api/analysis/upload_dynamic",
            json={"jobId": job_id, "fileName": "sample.exe", "status": "running", "runId": "run1"},
        )
        assert running.status_code == 200
        assert running.json()["analysisType"] == "both"
        assert running.json()["status"] == "running"

        completed = client.post(
            "/api/analysis/upload_dynamic",
            json={
                "jobId": job_id,
                "fileName": "sample.exe",
                "report": "comportamento na VM",
                "status": "completed",
                "runId": "run1",
            },
        )
        assert completed.status_code == 200
        assert completed.json()["status"] == "completed"

        detail = client.get(f"/api/analysis/{job_id}").json()
        assert detail["analysisType"] == "both"
        assert detail["staticResult"]["report"] == "estático"
        assert "comportamento na VM" in detail["dynamicResult"]["dynamicReportText"]

    def test_estatica_concluida_nao_fecha_job_com_vm_em_curso(self, client):
        running = client.post(
            "/api/analysis/upload_dynamic",
            json={"fileName": "sample.exe", "status": "running", "runId": "run1"},
        )
        assert running.status_code == 200
        job_id = running.json()["jobId"]
        assert running.json()["status"] == "running"

        static = client.post(
            "/api/analysis/upload_static",
            json={
                "jobId": job_id,
                "fileName": "sample.exe",
                "report": "estático",
                "cCode": "void main(){}",
                "ilCode": "IL",
                "riskScore": 10,
                "riskLevel": "LOW",
                "status": "completed",
            },
        )
        assert static.status_code == 200
        assert static.json()["analysisType"] == "both"
        assert static.json()["status"] == "running"

        detail = client.get(f"/api/analysis/{job_id}").json()
        assert detail["status"] == "running"
        assert detail["analysisType"] == "both"
        assert detail["staticResult"]["report"] == "estático"
        assert not (detail["dynamicResult"].get("dynamicReportText") or "").strip()

    def test_job_inexistente_404(self, client):
        missing = str(uuid.uuid4())
        r = client.post(
            "/api/analysis/upload_dynamic",
            json={"jobId": missing, "status": "running"},
        )
        assert r.status_code == 404
