# --- Módulo: middleware ---
# Middleware HTTP: rate limiting de uploads e correlação de job_id nos logs.

from __future__ import annotations

import logging
import os
import re
import time
from collections import defaultdict
from threading import Lock

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from observability import increment, job_id_ctx

logger = logging.getLogger("rat_analyzer_api")

_JOB_ID_PATH = re.compile(
    r"^/api/analysis/([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})",
    re.IGNORECASE,
)

_UPLOAD_PATHS = frozenset({"/api/analyze", "/api/analyze_stream", "/api/analysis"})

_RATE_LOCK = Lock()
_RATE_BUCKETS: dict[str, list[float]] = defaultdict(list)


# --- Limite de uploads por minuto (env RATANALYZER_RATE_LIMIT_UPLOADS_PER_MIN) ---
def _rate_limit_per_minute() -> int:
    raw = (os.environ.get("RATANALYZER_RATE_LIMIT_UPLOADS_PER_MIN") or "60").strip()
    try:
        return max(1, int(raw))
    except ValueError:
        return 60


# --- Extração do IP do cliente (X-Forwarded-For ou socket) ---
def _client_ip(request: Request) -> str:
    forwarded = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    if forwarded:
        return forwarded
    if request.client:
        return request.client.host
    return "unknown"


# --- Contagem de pedidos na janela deslizante de 60 s ---
def _prune_and_count(timestamps: list[float], now: float, window: float) -> int:
    cutoff = now - window
    while timestamps and timestamps[0] < cutoff:
        timestamps.pop(0)
    return len(timestamps)


# --- Reset do rate limiter (apenas para testes) ---
def reset_rate_limit_buckets() -> None:
    with _RATE_LOCK:
        _RATE_BUCKETS.clear()


# --- Middleware que propaga job_id para logs ---
class JobIdLoggingMiddleware(BaseHTTPMiddleware):
# --- Dispatch ---
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        match = _JOB_ID_PATH.match(request.url.path)
        token = job_id_ctx.set(match.group(1) if match else None)
        try:
            return await call_next(request)
        finally:
            job_id_ctx.reset(token)


# --- Middleware de rate limit por IP em endpoints de upload ---
class UploadRateLimitMiddleware(BaseHTTPMiddleware):
# --- Dispatch ---
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if request.method != "POST" or request.url.path not in _UPLOAD_PATHS:
            return await call_next(request)

        limit = _rate_limit_per_minute()
        ip = _client_ip(request)
        now = time.monotonic()

        with _RATE_LOCK:
            bucket = _RATE_BUCKETS[ip]
            count = _prune_and_count(bucket, now, 60.0)
            if count >= limit:
                increment("rat_analyzer_rate_limited_total")
                logger.warning("Rate limit excedido para %s em %s", ip, request.url.path)
                return JSONResponse(
                    status_code=429,
                    content={"detail": f"Limite de uploads excedido ({limit}/min). Tente novamente mais tarde."},
                )
            bucket.append(now)

        return await call_next(request)
