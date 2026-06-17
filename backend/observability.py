"""
Métricas e contexto de logging para observabilidade mínima.

Expõe contadores Prometheus em texto plano (sem dependência extra) e
propaga job_id nos logs via ContextVar.
"""

from __future__ import annotations

import contextvars
import logging
import threading
import time
from typing import Any

job_id_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar("job_id", default=None)

_START_TIME = time.monotonic()
_LOCK = threading.Lock()
_COUNTERS: dict[str, int] = {
    "rat_analyzer_analyze_requests_total": 0,
    "rat_analyzer_analyze_stream_requests_total": 0,
    "rat_analyzer_jobs_submitted_total": 0,
    "rat_analyzer_upload_static_total": 0,
    "rat_analyzer_upload_dynamic_total": 0,
    "rat_analyzer_rate_limited_total": 0,
    "rat_analyzer_errors_total": 0,
}


class JobIdFilter(logging.Filter):
    """Injeta job_id no registo de log (quando definido no contexto)."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.job_id = job_id_ctx.get() or "-"  # type: ignore[attr-defined]
        return True


def increment(counter: str, amount: int = 1) -> None:
    with _LOCK:
        _COUNTERS[counter] = _COUNTERS.get(counter, 0) + amount


def render_prometheus_metrics() -> str:
    uptime = time.monotonic() - _START_TIME
    lines = [
        "# HELP rat_analyzer_uptime_seconds Tempo desde o arranque do processo.",
        "# TYPE rat_analyzer_uptime_seconds gauge",
        f"rat_analyzer_uptime_seconds {uptime:.3f}",
    ]
    with _LOCK:
        for name, value in sorted(_COUNTERS.items()):
            metric_type = "counter"
            lines.append(f"# TYPE {name} {metric_type}")
            lines.append(f"{name} {value}")
    return "\n".join(lines) + "\n"


def check_yara_available() -> dict[str, Any]:
    try:
        import yara  # noqa: F401
    except ImportError:
        return {"status": "unavailable", "reason": "yara-python não instalado"}
    from pathlib import Path
    import config

    rules_dir = Path(config.YARA_RULES_DIR)
    if not rules_dir.is_dir():
        return {"status": "unavailable", "reason": "diretório yara_rules em falta"}
    rule_files = list(rules_dir.glob("*.yar"))
    if not rule_files:
        return {"status": "unavailable", "reason": "sem ficheiros .yar"}
    return {"status": "available", "rule_count": len(rule_files)}


def check_ghidra_configured() -> dict[str, Any]:
    import os

    install = (os.environ.get("GHIDRA_INSTALL_DIR") or "").strip()
    if not install:
        return {"status": "not_configured"}
    from pathlib import Path

    if Path(install).is_dir():
        return {"status": "configured", "path": install}
    return {"status": "invalid_path", "path": install}


def check_db_health() -> dict[str, Any]:
    try:
        import job_store

        job_store.init_db()
        return {"status": "ok"}
    except Exception as exc:  # noqa: BLE001
        return {"status": "error", "detail": str(exc)}
