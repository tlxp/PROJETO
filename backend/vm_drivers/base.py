from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Protocol, TYPE_CHECKING

if TYPE_CHECKING:
    from analysis_jobs import AnalysisJob


@dataclass(frozen=True)
class DynamicAnalysisOutput:
    summary: str
    behavior: Dict[str, Any]


class VMDriver(Protocol):
    """
    Interface mínima para drivers de sandbox dinâmica.

    Um driver é responsável por executar a amostra numa sandbox (VM) e devolver
    um relatório comportamental.
    """

    name: str

    def run(self, job: "AnalysisJob") -> DynamicAnalysisOutput: ...

