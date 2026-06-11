"""
Driver Proxmox (skeleton).

Este driver fala com:
  - API do Proxmox (rollback snapshot, start VM)
  - VM Agent (upload/run/report)

Ele é "fail-safe": se faltar configuração ou o agent não responder, devolve erro
explícito e não tenta "inventar" resultados.
"""

from __future__ import annotations

from dataclasses import dataclass
import os
import time
import urllib.parse
from typing import Any, Dict, Optional, TYPE_CHECKING

import requests

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob
from .base import DynamicAnalysisOutput


def _agent_headers() -> Dict[str, str]:
    """Header de autenticação do VM agent (env VM_AGENT_TOKEN, opcional)."""
    token = (os.environ.get("VM_AGENT_TOKEN") or "").strip()
    if token:
        return {"X-Agent-Token": token}
    return {}


def _q(value: Any) -> str:
    """URL-encode de um segmento de path da API Proxmox."""
    return urllib.parse.quote(str(value), safe="")


@dataclass(frozen=True)
class ProxmoxConfig:
    api_url: str
    token_id: str
    token_secret: str
    node: str
    vmid: int
    snapshot: str
    agent_base_url: str

    # Execução / timeouts
    http_timeout_seconds: int = 20
    # Timeout dedicado (mais alto) para operações de snapshot/start.
    vm_op_timeout_seconds: int = 120
    boot_wait_seconds: int = 120
    agent_wait_seconds: int = 120
    dynamic_timeout_seconds: int = 300


class ProxmoxVMDriver:
    name = "proxmox"

    def __init__(self, cfg: ProxmoxConfig):
        self.cfg = cfg

    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput:
        self._validate_cfg()

        node = _q(self.cfg.node)
        vmid = _q(self.cfg.vmid)
        snapshot = _q(self.cfg.snapshot)

        # 1) Reverter snapshot limpo
        self._proxmox_post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot/{snapshot}/rollback",
            json={},
            timeout=self.cfg.vm_op_timeout_seconds,
        )

        # 2) Garantir VM ligada
        self._proxmox_post(
            f"/api2/json/nodes/{node}/qemu/{vmid}/status/start",
            json={},
            timeout=self.cfg.vm_op_timeout_seconds,
        )

        # 3) Esperar o boot da VM e que o agent esteja pronto.
        #    boot_wait_seconds dá tempo ao SO convidado; o polling decorre
        #    durante esse período (sai mais cedo se o agent responder).
        self._wait_for_agent_ready(
            total_wait_seconds=self.cfg.boot_wait_seconds + self.cfg.agent_wait_seconds
        )

        # 4) Upload do sample para o agent
        self._agent_upload(job)

        # 5) Executar + recolher relatório
        self._agent_run(timeout_seconds=self.cfg.dynamic_timeout_seconds)
        behavior = self._agent_get_report()

        summary = "Análise dinâmica concluída via Proxmox + VM Agent."
        if isinstance(behavior, dict):
            behavior.setdefault("sandboxEngine", "proxmox")
            behavior.setdefault("vmid", self.cfg.vmid)
            behavior.setdefault("node", self.cfg.node)

        return DynamicAnalysisOutput(summary=summary, behavior=behavior if isinstance(behavior, dict) else {"raw": behavior})

    def _validate_cfg(self) -> None:
        missing = []
        if not self.cfg.api_url:
            missing.append("PROXMOX_API_URL")
        if not self.cfg.token_id:
            missing.append("PROXMOX_TOKEN_ID")
        if not self.cfg.token_secret:
            missing.append("PROXMOX_TOKEN_SECRET")
        if not self.cfg.node:
            missing.append("PROXMOX_NODE")
        if not self.cfg.vmid:
            missing.append("PROXMOX_VMID")
        if not self.cfg.snapshot:
            missing.append("PROXMOX_SNAPSHOT")
        if not self.cfg.agent_base_url:
            missing.append("VM_AGENT_BASE_URL")
        if missing:
            raise ValueError(f"Config Proxmox incompleta. Variáveis em falta: {', '.join(missing)}")

    def _proxmox_headers(self) -> Dict[str, str]:
        # Formato: "PVEAPIToken=USER@REALM!TOKENID=SECRET"
        return {
            "Authorization": f"PVEAPIToken={self.cfg.token_id}={self.cfg.token_secret}",
        }

    def _proxmox_post(self, path: str, json: Dict[str, Any], timeout: Optional[int] = None) -> Dict[str, Any]:
        url = self.cfg.api_url.rstrip("/") + path
        r = requests.post(
            url,
            headers=self._proxmox_headers(),
            json=json,
            timeout=timeout if timeout is not None else self.cfg.http_timeout_seconds,
            verify=True,
        )
        if not r.ok:
            raise RuntimeError(f"Proxmox API falhou ({r.status_code}): {r.text[:500]}")
        try:
            return r.json()
        except Exception:  # noqa: BLE001
            return {"raw": r.text}

    def _agent_url(self, path: str) -> str:
        return self.cfg.agent_base_url.rstrip("/") + path

    def _wait_for_agent_ready(self, total_wait_seconds: Optional[int] = None) -> None:
        wait = int(total_wait_seconds if total_wait_seconds is not None else self.cfg.agent_wait_seconds)
        deadline = time.time() + max(1, wait)
        last_err: Optional[str] = None
        while time.time() < deadline:
            try:
                r = requests.get(self._agent_url("/api/health"), headers=_agent_headers(), timeout=5)
                if r.ok:
                    return
                last_err = f"{r.status_code} {r.text[:200]}"
            except Exception as e:  # noqa: BLE001
                last_err = str(e)
            time.sleep(2)
        raise TimeoutError(f"VM agent não ficou pronto a tempo. Último erro: {last_err}")

    def _agent_upload(self, job: "AnalysisJob") -> None:
        with open(job.sample_path, "rb") as f:
            files = {"file": (job.sample_path.name, f, "application/octet-stream")}
            r = requests.post(self._agent_url("/api/upload"), files=files, headers=_agent_headers(), timeout=self.cfg.http_timeout_seconds)
        if not r.ok:
            raise RuntimeError(f"Upload para VM agent falhou ({r.status_code}): {r.text[:500]}")

    def _agent_run(self, timeout_seconds: int) -> None:
        payload = {"timeoutSeconds": int(timeout_seconds)}
        r = requests.post(self._agent_url("/api/run"), json=payload, headers=_agent_headers(), timeout=self.cfg.http_timeout_seconds)
        if not r.ok:
            raise RuntimeError(f"Execução no VM agent falhou ({r.status_code}): {r.text[:500]}")

    def _agent_get_report(self) -> Any:
        r = requests.get(self._agent_url("/api/report"), headers=_agent_headers(), timeout=self.cfg.http_timeout_seconds)
        if not r.ok:
            raise RuntimeError(f"Obter relatório do VM agent falhou ({r.status_code}): {r.text[:500]}")
        try:
            return r.json()
        except Exception:  # noqa: BLE001
            return {"raw": r.text}


__all__ = ["ProxmoxConfig", "ProxmoxVMDriver"]

