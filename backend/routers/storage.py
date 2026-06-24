# --- Módulo: storage ---
# Endpoints de manutenção de armazenamento.

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException

import config
import job_store
from storage_maintenance import archive_cold_jobs, cleanup_job_artifacts, estimate_storage, purge_all_storage

from .deps import require_api_token
from .schemas import StorageArchiveRequest, StorageCleanupRequest

logger = logging.getLogger("rat_analyzer_api")

router = APIRouter(tags=["storage"])


# --- Estimativa de espaço em disco por categoria ---
@router.get("/api/storage/estimate")
async def storage_estimate() -> dict:
    est = estimate_storage(project_root=config.PROJECT_ROOT)
    return {
        "paths": {
            "dataDir": str(getattr(config, "DATA_DIR", "")),
            "sandboxJobsDir": str(config.SANDBOX_JOBS_DIR),
            "reportsDir": str(config.REPORTS_DIR),
            "decompiledDir": str(config.DECOMPILED_DIR),
        },
        "bytes": {
            "sandboxJobs": est.sandbox_jobs_bytes,
            "reports": est.reports_bytes,
            "decompiled": est.decompiled_bytes,
            "pythonCache": est.python_cache_bytes,
            "wpfBuild": est.wpf_build_bytes,
            "frontendDist": est.frontend_dist_bytes,
            "total": est.total_bytes,
        },
    }


# --- Limpeza de artefactos antigos (retenção soft) ---
@router.post("/api/storage/cleanup", dependencies=[Depends(require_api_token)])
async def storage_cleanup(req: StorageCleanupRequest) -> dict:
    result = cleanup_job_artifacts(req.retentionDays, req.keepMostRecent)
    return {"ok": True, "result": result}


# --- Arquivo frio de jobs antigos (zip + remoção de out/) ---
@router.post("/api/storage/archive", dependencies=[Depends(require_api_token)])
async def storage_archive(req: StorageArchiveRequest) -> dict:
    result = archive_cold_jobs(req.olderThanDays)
    return {"ok": True, "result": result}


# --- Purga completa de storage (bloqueia se jobs em execução) ---
@router.post("/api/storage/purge", dependencies=[Depends(require_api_token)])
async def storage_purge() -> dict:
    try:
        running = job_store.count_jobs_by_status("running")
    except Exception:
        logger.exception("Falha ao verificar jobs em execução antes do purge.")
        running = 0
    if running > 0:
        raise HTTPException(409, f"Existem {running} job(s) em execução. Aguarde a conclusão antes de purgar.")
    result = purge_all_storage()
    return {"ok": True, "result": result}
