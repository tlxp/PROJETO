# --- Módulo: stub ---
# Driver seguro que simula análise dinâmica sem executar a amostra.

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, TYPE_CHECKING

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob

from .base import DynamicAnalysisOutput


# --- Driver stub (sem execução real) ---
class StubVMDriver:
    name = "stub"

    # --- Geração de relatório comportamental simulado ---
    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput:
        started_at = datetime.now(timezone.utc).isoformat()
        sample_name = job.sample_path.name

        behavior: Dict[str, Any] = {
            "status": "stub",
            "sandboxEngine": "stub",
            "sample": {
                "fileName": sample_name,
                "jobId": job.id,
            },
            "note": (
                "Relatório gerado por driver stub (sem execução real). "
                "Configure SANDBOX_VM_DRIVER e implemente um driver real "
                "(ex.: proxmox) para recolher comportamento verdadeiro."
            ),
            "timeline": [],
            "processes": [],
            "fileSystem": [],
            "registry": [],
            "network": [],
            "mutexes": [],
            "persistence": [],
            "privilegeEscalation": [],
            "sensitiveApiCalls": [],
            "startedAt": started_at,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
        }

        return DynamicAnalysisOutput(
            summary=(
                "Análise dinâmica simulada (stub). "
                "A sandbox de VMs real ainda não está ligada."
            ),
            behavior=behavior,
        )
