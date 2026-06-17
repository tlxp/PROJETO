# ADR 001: Dois caminhos de análise dinâmica

## Estado

Aceite

## Contexto

A análise comportamental exige VM isolada. Telemetria completa (ficheiros, registry, rede) é difícil de obter via HTTP simples; o pipeline PowerShell Hyper-V já existia com PsDirect e SHA256.

## Decisão

Manter **dois caminhos independentes**:

- **Caminho A** — `vm_orchestrator` + vm-agent HTTP (telemetria básica)
- **Caminho B** — WPF / `04-Run-Sample.ps1` (telemetria completa)

Ambos publicam no mesmo backend (`upload_dynamic`) para unificar o frontend em `/analysis/{jobId}`.

## Consequências

- Documentação e testes duplicados parcialmente
- Utilizador deve escolher o caminho adequado (tabela em `docs/README.md`)
- Driver `stub` por defeito para dev seguro
