# --- Módulo: hyperv ---
# Driver Hyper-V (Windows): snapshot, arranque VM e comunicação com VM Agent via HTTP.

from __future__ import annotations

import logging
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional, TYPE_CHECKING

import requests

from .base import DynamicAnalysisOutput

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob

_LOGGER = logging.getLogger("rat_analyzer_vm_hyperv")

# *Allowlist estrita para nomes de VM/snapshot em comandos PowerShell*
_SAFE_PS_NAME_RE = re.compile(r"^[A-Za-z0-9 ._\-]+$")


# --- Headers de autenticação do VM Agent ---
def _agent_headers() -> Dict[str, str]:
    token = (os.environ.get("VM_AGENT_TOKEN") or "").strip()
    if token:
        return {"X-Agent-Token": token}
    return {}


# --- Configuração do driver Hyper-V ---
@dataclass(frozen=True)
class HyperVConfig:
    vm_name: str
    snapshot_name: str
    agent_base_url: str

    http_timeout_seconds: int = 20
    vm_op_timeout_seconds: int = 120
    boot_wait_seconds: int = 120
    agent_wait_seconds: int = 120
    dynamic_timeout_seconds: int = 300


# --- Driver de análise dinâmica via Hyper-V ---
class HyperVVMDriver:
    name = "hyperv"

# --- Associa configuração Hyper-V ao driver ---
    def __init__(self, cfg: HyperVConfig):
        self.cfg = cfg

    # --- Pipeline completo: snapshot → boot → upload → run → report ---
    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput:
        self._validate_cfg()

        # *1) Restaurar snapshot limpo*
        self._ps(
            f'Restore-VMSnapshot -VMName "{self.cfg.vm_name}" -Name "{self.cfg.snapshot_name}" -Confirm:$false',
            timeout=self.cfg.vm_op_timeout_seconds,
        )

        # *2) Arrancar VM*
        self._ps(
            f'Start-VM -Name "{self.cfg.vm_name}" | Out-Null',
            timeout=self.cfg.vm_op_timeout_seconds,
        )

        # *3) Esperar boot e agent pronto*
        self._wait_for_agent_ready(
            total_wait_seconds=self.cfg.boot_wait_seconds + self.cfg.agent_wait_seconds
        )

        # *4) Upload da amostra*
        self._agent_upload(job)

        # *5) Executar e recolher relatório*
        self._agent_run(timeout_seconds=self.cfg.dynamic_timeout_seconds)
        behavior = self._agent_get_report()

        summary = "Análise dinâmica concluída via Hyper-V + VM Agent."
        if isinstance(behavior, dict):
            behavior.setdefault("sandboxEngine", "hyperv")
            behavior.setdefault("vmName", self.cfg.vm_name)

        return DynamicAnalysisOutput(
            summary=summary,
            behavior=behavior if isinstance(behavior, dict) else {"raw": behavior},
        )

    # --- Validação de configuração e allowlist de nomes ---
    def _validate_cfg(self) -> None:
        if not sys.platform.startswith("win"):
            raise RuntimeError("Driver Hyper-V só é suportado em Windows.")

        missing = []
        if not self.cfg.vm_name:
            missing.append("HYPERV_VM_NAME")
        if not self.cfg.snapshot_name:
            missing.append("HYPERV_SNAPSHOT_NAME")
        if not self.cfg.agent_base_url:
            missing.append("VM_AGENT_BASE_URL")
        if missing:
            raise ValueError(
                f"Config Hyper-V incompleta. Variáveis em falta: {', '.join(missing)}"
            )

        for label, value in (
            ("HYPERV_VM_NAME", self.cfg.vm_name),
            ("HYPERV_SNAPSHOT_NAME", self.cfg.snapshot_name),
        ):
            if not _SAFE_PS_NAME_RE.match(value):
                raise ValueError(
                    f"{label} contém caracteres inválidos. "
                    "Permitidos: letras, dígitos, espaço, ponto, hífen e underscore."
                )

    # --- Execução de comando PowerShell não interativo ---
    def _ps(self, command: str, timeout: int) -> None:
        completed = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                command,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"Comando Hyper-V falhou ({completed.returncode}): {completed.stderr[:500]}"
            )

    # --- Construção de URL do VM Agent ---
    def _agent_url(self, path: str) -> str:
        return self.cfg.agent_base_url.rstrip("/") + path

    # --- Polling até o VM Agent responder em /api/health ---
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
        raise TimeoutError(f"VM agent (Hyper-V) não ficou pronto a tempo. Último erro: {last_err}")

    # --- Upload da amostra para o VM Agent ---
    def _agent_upload(self, job: "AnalysisJob") -> None:
        with open(job.sample_path, "rb") as f:
            files = {"file": (job.sample_path.name, f, "application/octet-stream")}
            r = requests.post(
                self._agent_url("/api/upload"),
                files=files,
                headers=_agent_headers(),
                timeout=self.cfg.http_timeout_seconds,
            )
        if not r.ok:
            raise RuntimeError(
                f"Upload para VM agent (Hyper-V) falhou ({r.status_code}): {r.text[:500]}"
            )

    # --- Pedido de execução da amostra no VM Agent ---
    def _agent_run(self, timeout_seconds: int) -> None:
        payload = {"timeoutSeconds": int(timeout_seconds)}
        r = requests.post(
            self._agent_url("/api/run"),
            json=payload,
            headers=_agent_headers(),
            timeout=self.cfg.http_timeout_seconds,
        )
        if not r.ok:
            raise RuntimeError(
                f"Execução no VM agent (Hyper-V) falhou ({r.status_code}): {r.text[:500]}"
            )

    # --- Obtenção do relatório comportamental ---
    def _agent_get_report(self) -> Any:
        r = requests.get(
            self._agent_url("/api/report"),
            headers=_agent_headers(),
            timeout=self.cfg.http_timeout_seconds,
        )
        if not r.ok:
            raise RuntimeError(
                f"Obter relatório do VM agent (Hyper-V) falhou ({r.status_code}): {r.text[:500]}"
            )
        try:
            return r.json()
        except Exception:  # noqa: BLE001
            return {"raw": r.text}


__all__ = ["HyperVConfig", "HyperVVMDriver"]
