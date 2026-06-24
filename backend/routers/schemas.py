# --- Módulo: schemas ---
# Modelos Pydantic partilhados pelos routers.

from pydantic import BaseModel


# --- Payload de upload/atualização de análise estática ---
class StaticAnalysisUpload(BaseModel):
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


# --- Payload de upload/atualização de análise dinâmica (Caminho B) ---
class DynamicAnalysisUpload(BaseModel):
    jobId: str | None = None
    fileName: str = ""
    report: str = ""
    dynamicSummary: str | None = None
    runId: str | None = None
    status: str = "completed"
    error: str | None = None


# --- Pedido de limpeza de storage ---
class StorageCleanupRequest(BaseModel):
    retentionDays: int = 30
    keepMostRecent: int = 200


# --- Pedido de arquivo frio de jobs ---
class StorageArchiveRequest(BaseModel):
    olderThanDays: int = 30
