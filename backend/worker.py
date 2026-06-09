"""
Worker RQ para processar jobs de análise (estática/dinâmica).

Uso:
  set REDIS_URL=redis://localhost:6379/0
  python worker.py
"""

from __future__ import annotations

import os

from rq import Worker

from task_queue import get_queue, get_redis


def main() -> None:
    qname = os.getenv("RQ_QUEUE") or "analysis"
    queue = get_queue(qname)
    w = Worker([queue], connection=get_redis())
    w.work(with_scheduler=False)


if __name__ == "__main__":
    main()

