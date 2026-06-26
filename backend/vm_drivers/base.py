# --- Módulo: base ---
# Interface mínima para drivers de sandbox dinâmica (Protocol + dataclass de saída).

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Protocol, TYPE_CHECKING

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob


# --- Resultado estruturado de análise dinâmica ---
@dataclass(frozen=True)
class DynamicAnalysisOutput:
    summary: str
    behavior: Dict[str, Any]


# --- Protocolo que todo o driver de VM deve implementar ---
class VMDriver(Protocol):
    name: str

# --- Executa análise dinâmica na VM ---
    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput: ...
