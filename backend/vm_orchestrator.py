from __future__ import annotations

"""
Orquestrador de VMs para análise dinâmica.

O orquestrador escolhe um "driver" (stub/proxmox/...) via variável de ambiente,
permitindo evoluir para uma sandbox real sem alterar o resto do sistema.
"""

import os
from typing import Any, Dict, TYPE_CHECKING

from vm_drivers.base import DynamicAnalysisOutput
from vm_drivers.proxmox import ProxmoxConfig, ProxmoxVMDriver
from vm_drivers.stub import StubVMDriver
from vm_drivers.hyperv import HyperVConfig, HyperVVMDriver

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob


def _get_driver_name() -> str:
    return (os.getenv("SANDBOX_VM_DRIVER") or "stub").strip().lower()


def _build_driver():
    name = _get_driver_name()
    if name in ("stub", "safe", "disabled"):
        return StubVMDriver()

    if name == "proxmox":
        # Config via env para evitar hardcode e facilitar deploy.
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
            boot_wait_seconds=int(os.getenv("SANDBOX_BOOT_WAIT_SECONDS") or "120"),
            agent_wait_seconds=int(os.getenv("SANDBOX_AGENT_WAIT_SECONDS") or "120"),
            dynamic_timeout_seconds=int(os.getenv("SANDBOX_DYNAMIC_TIMEOUT_SECONDS") or "300"),
        )
        return HyperVVMDriver(cfg)

    raise ValueError(
        f"SANDBOX_VM_DRIVER inválido: {name!r}. Valores suportados: stub, proxmox, hyperv."
    )


def run_dynamic_analysis(job: AnalysisJob) -> Dict[str, Any]:
    driver = _build_driver()
    out: DynamicAnalysisOutput = driver.run(job)
    return {"summary": out.summary, "behavior": out.behavior, "driver": driver.name}


__all__ = ["run_dynamic_analysis"]

