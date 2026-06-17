"""Modelos Pydantic partilhados pelos routers."""

from pydantic import BaseModel


class StaticAnalysisUpload(BaseModel):
    """Publica (ou actualiza) análise estática — suporta estado `running`."""

    jobId: str | None = None
    fileName: str = ""
    report: str = ""
    cCode: str = ""
    ilCode: str = ""
    riskScore: int = 0
    riskLevel: str = ""
    flaggedIndicators: list[str] | None = None
    flaggedFunctions: list[dict] | None = None
    status: str = "completed"
    staticProgress: float | None = None
    error: str | None = None


class DynamicAnalysisUpload(BaseModel):
    """Publica (ou actualiza) o resultado de análise dinâmica na VM (Caminho B)."""

    jobId: str | None = None
    fileName: str = ""
    report: str = ""
    dynamicSummary: str | None = None
    runId: str | None = None
    status: str = "completed"
    error: str | None = None


class StorageCleanupRequest(BaseModel):
    retentionDays: int = 30
    keepMostRecent: int = 200


class StorageArchiveRequest(BaseModel):
    olderThanDays: int = 30
