# --- Módulo: vm_orchestrator ---
# Orquestrador de VMs: escolhe driver (stub/proxmox/hyperv) via variável de ambiente.

from __future__ import annotations

import logging
import os
from typing import Any, Dict, TYPE_CHECKING

logger = logging.getLogger(__name__)

from vm_drivers.base import DynamicAnalysisOutput
from vm_drivers.proxmox import ProxmoxConfig, ProxmoxVMDriver
from vm_drivers.stub import StubVMDriver
from vm_drivers.hyperv import HyperVConfig, HyperVVMDriver

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob


# --- Nome do driver a partir de SANDBOX_VM_DRIVER (vazio se não definido) ---
def _get_driver_name() -> str:
    return (os.getenv("SANDBOX_VM_DRIVER") or "").strip().lower()


# --- Instanciação do driver conforme configuração ---
def _build_driver():
    name = _get_driver_name()
    if not name:
        raise RuntimeError(
            "Análise dinâmica não configurada: a variável SANDBOX_VM_DRIVER não está definida. "
            "Defina-a em backend/.env (ou no ambiente) — ex.: SANDBOX_VM_DRIVER=hyperv com "
            "HYPERV_VM_NAME, HYPERV_SNAPSHOT_NAME, VM_AGENT_BASE_URL e VM_AGENT_TOKEN. "
            "Ver backend/.env.example e docs/sandbox-hyperv-setup.md. "
            "Para um relatório simulado (sem executar a amostra), use SANDBOX_VM_DRIVER=stub."
        )

    from vm_drivers import warn_if_experimental

    warn_if_experimental(name)
    if name in ("stub", "safe", "disabled"):
        return StubVMDriver()

    if name == "proxmox":
        logger.warning(
            "SANDBOX_VM_DRIVER=proxmox é experimental (sem guia nem testes de integração). "
            "Para produção use hyperv (Caminho A) ou o pipeline PowerShell (Caminho B)."
        )
        # *Config via env para evitar hardcode*
        api_url = os.getenv("PROXMOX_API_URL") or ""
        token_id = os.getenv("PROXMOX_TOKEN_ID") or ""
        token_secret = os.getenv("PROXMOX_TOKEN_SECRET") or ""
        node = os.getenv("PROXMOX_NODE") or ""
        vmid_raw = os.getenv("PROXMOX_VMID") or ""
        snapshot = os.getenv("PROXMOX_SNAPSHOT") or ""
        agent_base_url = os.getenv("VM_AGENT_BASE_URL") or ""

        try:
            vmid = int(vmid_raw)
        except Exception:  # noqa: BLE001
            vmid = 0

        cfg = ProxmoxConfig(
            api_url=api_url,
            token_id=token_id,
            token_secret=token_secret,
            node=node,
            vmid=vmid,
            snapshot=snapshot,
            agent_base_url=agent_base_url,
            http_timeout_seconds=int(os.getenv("SANDBOX_HTTP_TIMEOUT_SECONDS") or "20"),
            vm_op_timeout_seconds=int(os.getenv("SANDBOX_VM_OP_TIMEOUT_SECONDS") or "120"),
            boot_wait_seconds=int(os.getenv("SANDBOX_BOOT_WAIT_SECONDS") or "120"),
            agent_wait_seconds=int(os.getenv("SANDBOX_AGENT_WAIT_SECONDS") or "120"),
            dynamic_timeout_seconds=int(os.getenv("SANDBOX_DYNAMIC_TIMEOUT_SECONDS") or "300"),
        )
        return ProxmoxVMDriver(cfg)

    if name == "hyperv":
        vm_name = os.getenv("HYPERV_VM_NAME") or ""
        snapshot = os.getenv("HYPERV_SNAPSHOT_NAME") or ""
        agent_base_url = os.getenv("VM_AGENT_BASE_URL") or ""

        cfg = HyperVConfig(
            vm_name=vm_name,
            snapshot_name=snapshot,
            agent_base_url=agent_base_url,
            http_timeout_seconds=int(os.getenv("SANDBOX_HTTP_TIMEOUT_SECONDS") or "20"),
            vm_op_timeout_seconds=int(os.getenv("SANDBOX_VM_OP_TIMEOUT_SECONDS") or "120"),
            boot_wait_seconds=int(os.getenv("SANDBOX_BOOT_WAIT_SECONDS") or "120"),
            agent_wait_seconds=int(os.getenv("SANDBOX_AGENT_WAIT_SECONDS") or "120"),
            dynamic_timeout_seconds=int(os.getenv("SANDBOX_DYNAMIC_TIMEOUT_SECONDS") or "300"),
        )
        return HyperVVMDriver(cfg)

    raise ValueError(
        f"SANDBOX_VM_DRIVER inválido: {name!r}. Valores suportados: stub, proxmox, hyperv."
    )


# --- Ponto de entrada da análise dinâmica para analysis_jobs ---
def run_dynamic_analysis(job: AnalysisJob) -> Dict[str, Any]:
    driver = _build_driver()
    out: DynamicAnalysisOutput = driver.run(job)
    return {"summary": out.summary, "behavior": out.behavior, "driver": driver.name}


__all__ = ["run_dynamic_analysis"]
