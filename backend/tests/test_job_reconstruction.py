"""
Teste do fix do worker RQ (item: job criado num processo pode ser
reconstruído da DB/disco e executado por _run_job noutro processo).

O pipeline pesado é substituído por fakes via monkeypatch.
"""

import os
import uuid

import pytest

import analysis_jobs
import job_store
from analysis_jobs import AnalysisResult, AnalysisType, JobStatus, _run_job, create_job


class _NoopExecutor:
    """Não executa nada: simula a criação do job sem o correr localmente."""

    def submit(self, fn, *args, **kwargs):
        return None


@pytest.fixture()
def no_local_run(monkeypatch):
    monkeypatch.setattr(analysis_jobs, "_get_executor", lambda: _NoopExecutor())


@pytest.fixture()
def fake_static(monkeypatch):
    def _fake_run_static(job):
        return AnalysisResult(
            report="relatório fake",
            cCode="// código fake",
            ilCode="// il fake",
            fileName=job.sample_path.name,
            riskScore=42,
            riskLevel="MEDIUM",
        )

    monkeypatch.setattr(analysis_jobs, "_run_static", _fake_run_static)


def test_job_reconstruido_da_db_e_executado(no_local_run, fake_static):
    # Conteúdo único para evitar reuso por cache (dedup sha256)
    contents = f"binario-{uuid.uuid4()}".encode()

    job = create_job("sample.exe", contents, AnalysisType.STATIC)
    assert job.status == JobStatus.QUEUED
    assert job.sample_path.exists()

    # Simular worker RQ noutro processo: o dict em memória não tem o job.
    with analysis_jobs._JOBS_LOCK:
        analysis_jobs._JOBS.pop(job.id, None)
    assert analysis_jobs.get_job(job.id) is None

    # O worker consegue reconstruir o job a partir da DB/disco e executá-lo.
    _run_job(job.id)

    row = job_store.get_job_row(job.id)
    assert row is not None
    assert row["status"] == JobStatus.COMPLETED.value
    static = row["staticResult"]
    assert static is not None
    assert static["fileName"] == "sample.exe"
    assert static["riskScore"] == 42


def test_fluxo_local_em_memoria_continua_a_funcionar(no_local_run, fake_static):
    contents = f"binario-{uuid.uuid4()}".encode()
    job = create_job("local.exe", contents, AnalysisType.STATIC)

    # Job permanece em memória (fluxo de threads local no Windows)
    assert analysis_jobs.get_job(job.id) is job

    _run_job(job.id)

    assert job.status == JobStatus.COMPLETED
    assert job.static_result is not None
    assert job.static_result.fileName == "local.exe"

    row = job_store.get_job_row(job.id)
    assert row is not None
    assert row["status"] == JobStatus.COMPLETED.value


def test_create_job_rejeita_filename_malicioso(no_local_run):
    with pytest.raises(ValueError):
        create_job("..\\..\\evil.exe", b"xyz", AnalysisType.STATIC)
