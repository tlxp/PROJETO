"""Testes de rate limiting em uploads."""

import pytest
from fastapi.testclient import TestClient

import api
from middleware import reset_rate_limit_buckets


@pytest.fixture()
def client():
    reset_rate_limit_buckets()
    return TestClient(api.app)


class TestRateLimit:
    def test_rate_limit_429(self, client, monkeypatch):
        monkeypatch.setenv("RATANALYZER_RATE_LIMIT_UPLOADS_PER_MIN", "2")

        class FakeAnalyzer:
            def __init__(self, *args, **kwargs):
                pass

            def analyze(self):
                return {"risk_score": 0, "risk_level": "LOW"}

        monkeypatch.setattr("routers.analyze.RATAnalyzer", FakeAnalyzer)

        for _ in range(2):
            r = client.post(
                "/api/analyze",
                files={"file": ("a.exe", b"MZ", "application/octet-stream")},
            )
            assert r.status_code == 200

        r = client.post(
            "/api/analyze",
            files={"file": ("b.exe", b"MZ", "application/octet-stream")},
        )
        assert r.status_code == 429
