from __future__ import annotations

import os
import sys

from redis import Redis


def redis_url() -> str | None:
    url = (os.getenv("REDIS_URL") or "").strip()
    return url or None


def is_queue_enabled() -> bool:
    # Em Windows, o RQ (versões recentes) pode falhar por depender de 'fork'.
    # Mantemos o backend funcional e fazemos fallback para threads locais.
    if sys.platform.startswith("win"):
        return False
    return redis_url() is not None


def get_redis() -> Redis:
    url = redis_url()
    if not url:
        raise RuntimeError("REDIS_URL não definido.")
    return Redis.from_url(url)


def get_queue(name: str = "analysis"):
    # Import lazy para não partir o arranque do API em ambientes sem RQ.
    try:
        from rq import Queue  # type: ignore
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(f"RQ não disponível neste ambiente: {e}")
    return Queue(name, connection=get_redis(), default_timeout=600)

