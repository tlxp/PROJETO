# ADR 002: Backend FastAPI modularizado em routers

## Estado

Aceite (2026-06)

## Contexto

`api.py` concentrava ~1100 linhas (endpoints, auth, uploads, storage), dificultando manutenção e revisão.

## Decisão

Separar em:

- `app_factory.py` — criação da app, middleware, lifespan
- `routers/analyze.py` — `/api/analyze`, `/api/analyze_stream`
- `routers/jobs.py` — pipeline de jobs
- `routers/health.py` — `/api/health`, `/metrics`
- `routers/storage.py` — manutenção de artefatos
- `routers/deps.py` — auth e helpers partilhados

`api.py` mantém-se como entrada `uvicorn api:app`.

## Consequências

- Imports de testes passam a fazer monkeypatch em `routers.analyze.RATAnalyzer`
- Novos endpoints devem ir para o router adequado
