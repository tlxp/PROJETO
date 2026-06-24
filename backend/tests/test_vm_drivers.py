# --- Módulo: test_vm_drivers ---
# Testes do orquestrador e drivers de VM (stub unitário; hyperv/proxmox com sandbox real).

from __future__ import annotations

import os
from pathlib import Path

import pytest

from analysis_jobs import AnalysisJob, AnalysisType
from vm_orchestrator import run_dynamic_analysis


# --- Helper interno: sample job ---
def _sample_job(tmp_path: Path) -> AnalysisJob:
    sample = tmp_path / "sample.exe"
    sample.write_bytes(b"MZ")
    return AnalysisJob(
        id="test-job-stub",
        analysis_type=AnalysisType.DYNAMIC,
        sample_path=sample,
        base_dir=tmp_path,
        output_dir=tmp_path / "out",
    )


# --- Testes de StubDriver ---
class TestStubDriver:
# --- Teste: verifica run dynamic analysis stub default ---
    def test_run_dynamic_analysis_stub_default(self, monkeypatch, tmp_path):
        monkeypatch.delenv("SANDBOX_VM_DRIVER", raising=False)
        job = _sample_job(tmp_path)

        result = run_dynamic_analysis(job)

        assert result["driver"] == "stub"
        assert "stub" in result["summary"].lower()
        assert result["behavior"]["status"] == "stub"
        assert result["behavior"]["sample"]["fileName"] == "sample.exe"


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("RUN_VM_DRIVER_INTEGRATION") != "1",
    reason="Defina RUN_VM_DRIVER_INTEGRATION=1 e configure Hyper-V + vm-agent (Caminho A)",
)
# --- Testes de HyperVDriverIntegration ---
class TestHyperVDriverIntegration:
# --- Teste: verifica hyperv driver end to end ---
    def test_hyperv_driver_end_to_end(self, tmp_path):
        # *Integração hyperv — requer VM, snapshot e VM_AGENT_**
        if os.getenv("SANDBOX_VM_DRIVER", "").lower() != "hyperv":
            pytest.skip("SANDBOX_VM_DRIVER=hyperv não definido")
        job = _sample_job(tmp_path)
        result = run_dynamic_analysis(job)
        assert result["driver"] == "hyperv"
        assert result["behavior"]


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("RUN_VM_DRIVER_INTEGRATION") != "1",
    reason="Defina RUN_VM_DRIVER_INTEGRATION=1 e configure Proxmox + vm-agent (experimental)",
)
# --- Testes de ProxmoxDriverIntegration ---
class TestProxmoxDriverIntegration:
# --- Teste: verifica proxmox driver end to end ---
    def test_proxmox_driver_end_to_end(self, tmp_path):
        # *Skeleton experimental — laboratório com Proxmox configurado*
        if os.getenv("SANDBOX_VM_DRIVER", "").lower() != "proxmox":
            pytest.skip("SANDBOX_VM_DRIVER=proxmox não definido")
        job = _sample_job(tmp_path)
        result = run_dynamic_analysis(job)
        assert result["driver"] == "proxmox"
        assert result["behavior"]
