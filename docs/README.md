# Documentação — RAT Analyzer

Índice da documentação do projeto. Para a visão geral e início rápido, ver o
[README principal](../README.md).

## Guias e especificações

| Documento | Conteúdo |
|-----------|----------|
| [`sandbox-hyperv-setup.md`](sandbox-hyperv-setup.md) | Guia completo da **análise dinâmica**: criar a VM no Hyper-V de raiz, variáveis de ambiente, endpoints da pipeline e protocolo do VM Agent. |
| [`ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md`](ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md) | Especificações de desenho da arquitetura **VM + Docker** (segurança, isolamento, integração com a webapp). |
| [`TODO_obfuscation_snippets.md`](TODO_obfuscation_snippets.md) | Notas e tarefas sobre a extração de excertos ofuscados. |

## Diagramas (PlantUML)

Os diagramas estão em [`diagrams/`](diagrams/) e podem ser renderizados com qualquer ferramenta PlantUML.

| Ficheiro | Diagrama |
|----------|----------|
| `analysis-sequence-overview.puml` | Sequência — visão integrada (estática + dinâmica) |
| `analysis-sequence-dynamic.puml` | Sequência — análise dinâmica em VM |
| `analysis-activity-static.puml` | Atividade — análise estática |
| `analysis-activity-dynamic.puml` | Atividade — análise dinâmica em VM |

Diagramas de engenharia de software (imagens) estão em [`engenharia-de-software/`](engenharia-de-software/):
arquitetura do sistema, backend core, fluxo de análise, frontend e ciclo de vida de um job.

## Documentação por componente

| Componente | README |
|------------|--------|
| Backend (API + pipeline) | [`../backend/README.md`](../backend/README.md) |
| Frontend (web) | [`../frontend/README.md`](../frontend/README.md) |
| Sandbox Hyper-V (serial) | [`../scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) |
| Protocolo serial SBXREP1 | [`../scripts/hyperv-sandbox/SERIAL_REPORT_PROTOCOL.md`](../scripts/hyperv-sandbox/SERIAL_REPORT_PROTOCOL.md) |
| Teste benigno da VM | [`../benign-vm-test/README.md`](../benign-vm-test/README.md) |
