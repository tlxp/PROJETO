"""
Driver Hyper-V (Windows host local).

Este driver:
  - Usa PowerShell/Hyper-V para restaurar snapshot e arrancar a VM
  - Fala com o VM Agent via HTTP (upload/run/report)

Boas práticas de segurança:
  - Só corre em Windows (falha noutros SOs)
  - Nome da VM e do snapshot vêm de variáveis de ambiente controladas (não
    aceitamos input do utilizador para esses campos)
  - Se a config estiver incompleta ou o agent não responder, falha com erro
    explícito (não inventa resultados)
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional, TYPE_CHECKING

import requests

from .base import DynamicAnalysisOutput

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob


@dataclass(frozen=True)
class HyperVConfig:
    vm_name: str
    snapshot_name: str
    agent_base_url: str

    http_timeout_seconds: int = 20
    boot_wait_seconds: int = 120
    agent_wait_seconds: int = 120
    dynamic_timeout_seconds: int = 300


class HyperVVMDriver:
    name = "hyperv"

    def __init__(self, cfg: HyperVConfig):
        self.cfg = cfg

    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput:
        self._validate_cfg()

        # 1) Restaurar snapshot limpo
        self._ps(
            f'Restore-VMSnapshot -VMName "{self.cfg.vm_name}" -Name "{self.cfg.snapshot_name}" -Confirm:$false',
            timeout=self.cfg.http_timeout_seconds,
        )

        # 2) Arrancar VM
        self._ps(
            f'Start-VM -Name "{self.cfg.vm_name}" | Out-Null',
            timeout=self.cfg.http_timeout_seconds,
        )

        # 3) Esperar que o agent fique pronto
        self._wait_for_agent_ready()

        # 4) Upload da amostra
        self._agent_upload(job)

        # 5) Executar + recolher relatório
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

        # Pequena validação para reduzir risco de comandos malformados
        for label, value in (
            ("HYPERV_VM_NAME", self.cfg.vm_name),
            ("HYPERV_SNAPSHOT_NAME", self.cfg.snapshot_name),
        ):
            if any(c in value for c in ['"', ";", "|"]):
                raise ValueError(
                    f"{label} contém caracteres inválidos para uso em PowerShell."
                )

    def _ps(self, command: str, timeout: int) -> None:
        """
        Executa um comando PowerShell de forma não interativa.
        """
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

    def _agent_url(self, path: str) -> str:
        return self.cfg.agent_base_url.rstrip("/") + path

    def _wait_for_agent_ready(self) -> None:
        deadline = time.time() + max(1, int(self.cfg.agent_wait_seconds))
        last_err: Optional[str] = None
        while time.time() < deadline:
            try:
                r = requests.get(self._agent_url("/api/health"), timeout=5)
                if r.ok:
                    return
                last_err = f"{r.status_code} {r.text[:200]}"
            except Exception as e:  # noqa: BLE001
                last_err = str(e)
            time.sleep(2)
        raise TimeoutError(f"VM agent (Hyper-V) não ficou pronto a tempo. Último erro: {last_err}")

    def _agent_upload(self, job: "AnalysisJob") -> None:
        with open(job.sample_path, "rb") as f:
            files = {"file": (job.sample_path.name, f, "application/octet-stream")}
            r = requests.post(
                self._agent_url("/api/upload"),
                files=files,
                timeout=self.cfg.http_timeout_seconds,
            )
        if not r.ok:
            raise RuntimeError(
                f"Upload para VM agent (Hyper-V) falhou ({r.status_code}): {r.text[:500]}"
            )

    def _agent_run(self, timeout_seconds: int) -> None:
        payload = {"timeoutSeconds": int(timeout_seconds)}
        r = requests.post(
            self._agent_url("/api/run"),
            json=payload,
            timeout=self.cfg.http_timeout_seconds,
        )
        if not r.ok:
            raise RuntimeError(
                f"Execução no VM agent (Hyper-V) falhou ({r.status_code}): {r.text[:500]}"
            )

    def _agent_get_report(self) -> Any:
        r = requests.get(
            self._agent_url("/api/report"),
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

