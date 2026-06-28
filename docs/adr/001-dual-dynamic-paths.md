# ADR 001: Dois caminhos de análise dinâmica

## Estado

Aceite

## Contexto

A análise comportamental exige VM isolada. Telemetria completa (ficheiros, registry, rede) é difícil de obter via HTTP simples; o pipeline PowerShell Hyper-V já existia com PsDirect e SHA256.

## Decisão

Manter **dois caminhos independentes**:

- **Caminho A** — `vm_orchestrator` + vm-agent HTTP (telemetria básica); entrada via **frontend web** (modos dinâmica/ambas) ou API
- **Caminho B** — WPF / `04-Run-Sample.ps1` (telemetria completa)

Ambos convergem no backend: Caminho A grava `dynamicResult` no job; Caminho B usa `upload_dynamic`. O frontend unifica visualização em `/analysis/{jobId}`.

## Entrada do utilizador

- **Web:** estática (stream), dinâmica ou ambas (Caminho A via `POST /api/analysis`)
- **WPF:** estática e/ou comportamental (Caminho B)

## Consequências

- Documentação e testes duplicados parcialmente
- Utilizador escolhe caminho conforme telemetria necessária (tabela em `docs/README.md`)
- Driver `stub` por defeito para dev seguro
