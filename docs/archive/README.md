# Documentação arquivada

Pasta para documentos **obsoletos** ou **desenhos alternativos não implementados**.

Documentação vigente: [`docs/README.md`](../README.md).

## Como arquivar

1. Mova o ficheiro para esta pasta (ou remova-o se for redundante com docs atuais).
2. Adicione no **topo** do documento:

   ```markdown
   > ⚠ Documento arquivado — não reflete o estado atual da codebase.
   > Consulte [`docs/README.md`](../README.md) para documentação vigente.
   ```

3. Atualize referências noutros `.md` e registe o item na tabela abaixo.

## Conteúdo arquivado

| Ficheiro | Motivo | Substituto |
|----------|--------|------------|
| [`ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md`](ESPECIFICACOES-ARQUITETURA-VM-DOCKER.md) | Arquitetura Docker não implementada | [`sandbox-hyperv-setup.md`](../sandbox-hyperv-setup.md) · [`scripts/hyperv-sandbox/README.md`](../../scripts/hyperv-sandbox/README.md) |
| [`TODO_obfuscation_snippets.md`](TODO_obfuscation_snippets.md) | Tarefas concluídas | `backend/modules/obfuscation_snippet_extractor.py` · API `/artifacts/obfuscated_snippets` |
| [`PROJECT_ANALYSIS_DOCUMENT.md`](PROJECT_ANALYSIS_DOCUMENT.md) | Análise inicial desatualizada | [`AUDITORIA.md`](../AUDITORIA.md) · [`SEGURANCA.md`](../SEGURANCA.md) |

## Assets removidos (não arquivados)

Substituídos por fonte canónica em [`docs/diagrams/`](../diagrams/) → `relatório/imagens/fig-4-*.png`:

| Item removido | Motivo | Substituto |
|---------------|--------|------------|
| `engenharia-de-software/*.png` | PNGs legados duplicados | [`docs/diagrams/`](../diagrams/) → `relatório/imagens/fig-4-*.png` |
| `diagrams/analysis-sequence-dynamic.puml` | Diagrama redundante | [`analysis-sequence-overview.puml`](../diagrams/analysis-sequence-overview.puml) · [`analysis-activity-dynamic.puml`](../diagrams/analysis-activity-dynamic.puml) |
