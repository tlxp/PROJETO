# Perguntas frequentes

Índice: [`docs/README.md`](README.md). Escolha do caminho dinâmico: [tabela em docs/README](README.md#análise-dinâmica--qual-caminho-usar).

## Segurança e tokens

Índice completo: [`SEGURANCA.md`](SEGURANCA.md). Checklist de deploy: [`production-secrets.md`](production-secrets.md#checklist-antes-de-deploy).

**Backend recusa arrancar** - Defina `RATANALYZER_API_TOKEN` ou desative modo produção. Ver [`production-secrets.md`](production-secrets.md).

**Frontend 401** - Defina `VITE_API_TOKEN` (= `RATANALYZER_API_TOKEN`) em `frontend/.env`; rebuild se produção.

**vm-agent termina ao arrancar** - Defina `VM_AGENT_TOKEN` ou use `VM_AGENT_ALLOW_INSECURE=1` **apenas** em dev local.

**Scripts Hyper-V pedem password** - Defina `PROJETOVM_GuestPassword`; não use `PROJETOVM_ALLOW_INSECURE_DEFAULTS` em produção.

## Análise estática

| Problema | Solução |
|----------|---------|
| YARA falha | Instalar YARA no PATH; regras em `yara_rules/` |
| Sem pseudo-C nativo | `GHIDRA_INSTALL_DIR` + `requirements-ghidra.lock` |
| Sem IL/C# | .NET SDK + `ilspycmd` (WPF pode instalar) |

## Análise dinâmica

**Relatório vazio no Caminho A** - Esperado: vm-agent com `monitoring: "not_implemented"`. Telemetria completa: **Caminho B**.

**vm-agent health check falha** - `VM_AGENT_TOKEN` igual host/VM; header `X-Agent-Token`; IP estático Internal; bind no IP da VM.

**Problemas no Caminho B** - [`scripts/hyperv-sandbox/TROUBLESHOOTING.md`](../scripts/hyperv-sandbox/TROUBLESHOOTING.md).

## WPF

Execute **como Administrador**. Python e Node no PATH para arranque automático do backend/frontend.

## Dados e testes

- Artefatos: `%LOCALAPPDATA%\RatAnalyzer` (`RATANALYZER_DATA_DIR`).
- Relatórios Caminho B: `D:\PROJETOVM\Reports\`.
- Testes: [`CONTRIBUTING.md`](../CONTRIBUTING.md).
