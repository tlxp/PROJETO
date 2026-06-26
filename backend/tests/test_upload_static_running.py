# --- Módulo: test_upload_static_running ---
# Testes do endpoint /api/analysis/upload_static (running + merge com job VM).

import uuid

import pytest
from fastapi.testclient import TestClient

import api


@pytest.fixture()
# --- Fixture: cliente HTTP de teste ---
def client():
    return TestClient(api.app)


# --- Testes de UploadStaticRunning ---
class TestUploadStaticRunning:
    def test_running_em_job_vm_existente(self, client):
        dynamic = client.post(
            "/api/analysis/upload_dynamic",
            json={
                "fileName": "sample.exe",
                "report": "relatório VM",
                "status": "completed",
            },
        )
        assert dynamic.status_code == 200
        job_id = dynamic.json()["jobId"]

        running = client.post(
            "/api/analysis/upload_static",
            json={
                "jobId": job_id,
                "fileName": "sample.exe",
                "status": "running",
                "staticProgress": 12.5,
            },
        )
        assert running.status_code == 200
        assert running.json()["analysisType"] == "both"
        assert running.json()["status"] == "running"

        detail = client.get(f"/api/analysis/{job_id}").json()
        assert detail["status"] == "running"
        assert detail["staticResult"]["staticProgress"] == 12.5
        assert "relatório VM" in detail["dynamicResult"]["dynamicReportText"]

    def test_cria_job_running_sem_job_id(self, client):
        running = client.post(
            "/api/analysis/upload_static",
            json={"fileName": "sample.exe", "status": "running", "staticProgress": 0},
        )
        assert running.status_code == 200
        job_id = running.json()["jobId"]
        assert uuid.UUID(job_id).version == 4
        assert client.get(f"/api/analysis/{job_id}").json()["status"] == "running"
