"""Factory da aplicação FastAPI."""

from __future__ import annotations

import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

_BACKEND_DIR = Path(__file__).resolve().parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

import config
import job_store
from middleware import JobIdLoggingMiddleware, UploadRateLimitMiddleware
from observability import JobIdFilter
from routers import analyze, health, jobs, storage
from security_config import validate_startup_secrets
from storage_maintenance import archive_cold_jobs, cleanup_job_artifacts

logger = logging.getLogger("rat_analyzer_api")


def _configure_logging() -> None:
    root = logging.getLogger()
    if not root.handlers:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s [%(levelname)s] [job=%(job_id)s] %(message)s",
        )
    job_filter = JobIdFilter()
    for handler in logging.getLogger().handlers:
        handler.addFilter(job_filter)
    logging.getLogger("rat_analyzer_api").addFilter(job_filter)


def _cors_origins() -> list[str]:
    raw = (os.environ.get("RATANALYZER_CORS_ORIGINS") or "").strip()
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]
    return [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
    ]


@asynccontextmanager
async def _lifespan(app: FastAPI):
    validate_startup_secrets()
    try:
        job_store.init_db()
        Path(config.REPORTS_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.DECOMPILED_DIR).mkdir(parents=True, exist_ok=True)
        Path(config.SANDBOX_JOBS_DIR).mkdir(parents=True, exist_ok=True)
    except Exception:
        logger.exception("Falha no startup ao inicializar diretórios/DB.")
    try:
        cleanup_job_artifacts(config.JOBS_RETENTION_DAYS, config.JOBS_MAX_COUNT)
    except Exception:
        logger.exception("Falha na limpeza de artefatos no startup (continua o arranque).")
    try:
        archive_cold_jobs(config.COLD_ARCHIVE_DAYS)
    except Exception:
        logger.exception("Falha no arquivo frio de jobs no startup (continua o arranque).")
    yield


def create_app() -> FastAPI:
    _configure_logging()
    application = FastAPI(
        title="RAT Analyzer API",
        version="1.0.0",
        description=(
            "API REST para análise de malware (estática e dinâmica). "
            "Documentação interativa em `/docs` (OpenAPI/Swagger)."
        ),
        lifespan=_lifespan,
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=_cors_origins(),
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Content-Type", "Accept", "X-API-Token"],
    )
    application.add_middleware(JobIdLoggingMiddleware)
    application.add_middleware(UploadRateLimitMiddleware)

    application.include_router(analyze.router)
    application.include_router(jobs.router)
    application.include_router(health.router)
    application.include_router(storage.router)
    return application
