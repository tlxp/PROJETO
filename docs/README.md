# Documentação — RAT Analyzer

Índice da documentação do projeto. Para a visão geral e início rápido, ver o
[README principal](../README.md).

> **Auditoria (Jun 2026):** remediação concluída a **100%** — [`AUDITORIA.md`](AUDITORIA.md).

## Dois caminhos de análise dinâmica

| Caminho | Documentação | Orquestrador |
|---------|--------------|--------------|
| **A — VM Agent (HTTP)** | [`sandbox-hyperv-setup.md`](sandbox-hyperv-setup.md) | Backend Python → `vm_drivers/hyperv.py` → `vm-agent` |
| **B — PowerShell serial** | [`../scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) | WPF ou `04-Run-Sample.ps1` → COM1 / Copy-VMFile |

## Guias e especificações

| Documento | Conteúdo |
|-----------|----------|
| [`AUDITORIA.md`](AUDITORIA.md) | **Auditoria concluída:** resumo por área, checklist de deploy, testes e manutenção contínua. |
| [`production-secrets.md`](production-secrets.md) | **Produção:** gerar e configurar `RATANALYZER_API_TOKEN`, `VM_AGENT_TOKEN`, `PROJETOVM_GuestPassword` (sem `ALLOW_INSECURE`). |
| [`ps1-scripts.md`](ps1-scripts.md) | **Scripts PowerShell:** UTF-8 BOM, CRLF e política de idioma (PT nas mensagens). |
| [`sandbox-hyperv-setup.md`](sandbox-hyperv-setup.md) | **Caminho A:** VM Agent, variáveis de ambiente do backend, segurança (`VM_AGENT_TOKEN`), guia manual Hyper-V. |
| [`../scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) | **Caminho B:** pipeline PowerShell (`D:\PROJETOVM`, `MalwareSandbox`, snapshot `CleanState`). |
| [`../scripts/hyperv-sandbox/SERIAL_REPORT_PROTOCOL.md`](../scripts/hyperv-sandbox/SERIAL_REPORT_PROTOCOL.md) | Protocolo serial implementado (`START_OF_REPORT` … linhas … `END_OF_REPORT`). |
| [`ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md`](ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md) | Desenho **alternativo/futuro** (Linux + Docker) — não implementado. |
| [`TODO_obfuscation_snippets.md`](TODO_obfuscation_snippets.md) | Notas sobre extração de excertos ofuscados. |
| [`archive/PROJECT_ANALYSIS_DOCUMENT.md`](archive/PROJECT_ANALYSIS_DOCUMENT.md) | Documento histórico de desenho (grafos, IA, Redis/RQ) — referência, não manual operacional. |

## Diagramas (PlantUML)

Os diagramas estão em [`diagrams/`](diagrams/) e podem ser renderizados com qualquer ferramenta PlantUML.

| Ficheiro | Diagrama |
|----------|----------|
| `analysis-sequence-overview.puml` | Sequência — visão integrada (estática + dinâmica) |
| `analysis-sequence-dynamic.puml` | Sequência — análise dinâmica em VM |
| `analysis-activity-static.puml` | Atividade — análise estática |
| `analysis-activity-dynamic.puml` | Atividade — análise dinâmica em VM |

Diagramas de engenharia de software (imagens) em [`engenharia-de-software/`](engenharia-de-software/):
arquitetura do sistema, backend core, fluxo de análise, frontend e ciclo de vida de um job.

## Documentação por componente

| Componente | README |
|------------|--------|
| Backend (API + pipeline) | [`../backend/README.md`](../backend/README.md) |
| Frontend (web) | [`../frontend/README.md`](../frontend/README.md) |
| VM Agent (.NET) | [`../vm-agent/`](../vm-agent/) (código + comentários em `Program.cs`) |
| Teste benigno da VM | [`../benign-vm-test/README.md`](../benign-vm-test/README.md) |
