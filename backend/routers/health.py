# --- Módulo: health ---
# --- Healthcheck enriquecido e métricas Prometheus ---

from __future__ import annotations

import os

from fastapi import APIRouter
from fastapi.responses import PlainTextResponse

import config
from observability import (
    check_db_health,
    check_ghidra_configured,
    check_yara_available,
    render_prometheus_metrics,
)
from security_config import api_token_configured

router = APIRouter(tags=["health"])


# --- Endpoint de saúde com estado de DB, YARA, Ghidra e driver VM ---
@router.get("/api/health")
async def health() -> dict:
    yara = check_yara_available()
    ghidra = check_ghidra_configured()
    db = check_db_health()
    overall = "ok" if db.get("status") == "ok" else "degraded"
    return {
        "status": overall,
        "version": "1.0.0",
        "db": db,
        "yara": yara,
        "ghidra": ghidra,
        "apiTokenConfigured": api_token_configured(),
        "vmDriver": (os.environ.get("SANDBOX_VM_DRIVER") or "stub").strip().lower(),
        "dataDir": str(config.DATA_DIR),
    }


# --- Métricas no formato Prometheus (text/plain) ---
@router.get("/metrics", response_class=PlainTextResponse)
async def metrics() -> PlainTextResponse:
    return PlainTextResponse(
        content=render_prometheus_metrics(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
