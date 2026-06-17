# ADR 003: Observabilidade mínima sem stack externa

## Estado

Aceite (2026-06)

## Contexto

Projeto académico/laboratório sem Prometheus/Grafana/Sentry em produção. Ainda assim é útil correlacionar logs por `job_id` e expor métricas básicas.

## Decisão

- **Logs** — `ContextVar` + filtro `job_id` em rotas `/api/analysis/{uuid}`
- **Métricas** — endpoint `/metrics` em formato Prometheus text (contadores em memória)
- **Health** — `/api/health` com estado de DB, YARA, Ghidra e driver VM

Sem dependências adicionais (sem `prometheus_client`, sem OpenTelemetry).

## Consequências

- Métricas reiniciam com o processo
- Para produção multi-instância, migrar para exporter dedicado
