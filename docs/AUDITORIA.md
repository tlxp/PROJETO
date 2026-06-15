# Auditoria de segurança e qualidade

Relatório de remediação do **RAT Analyzer** (10-11 Jun 2026).

> **Verificação:** 66 pytest · 37 Vitest · 48 xUnit · [CI](../.github/workflows/ci.yml)
> **Arquitetura de segurança:** [`SEGURANCA.md`](SEGURANCA.md) (documento canónico)

## Resumo por área

| Área | Principais correções | Estado |
|------|----------------------|--------|
| **Backend** | Auth em produção; uploads sanitizados; worker RQ; SQLite WAL; locks SHA-256 | Concluído |
| **.NET** | `VM_AGENT_TOKEN` obrigatório; bind local; MVVM; integridade SHA-256 em downloads | Concluído |
| **Frontend** | TS strict; Error Boundaries; `VITE_API_TOKEN`; Gemini client-side | Concluído |
| **Sandbox** | Isolamento de rede; guest password sem fallback inseguro; `try/finally`; UTF-8 CI | Concluído |
| **YARA** | Regras v2 correlacionadas + testes de compilação | Concluído |
| **Infra** | CI completo; `requirements*.lock`; testes xUnit (vm-agent + WPF) | Concluído |
| **Estrutura de segurança** | Zonas de confiança, mapa de auth, gestão de segredos, checklist - [`SEGURANCA.md`](SEGURANCA.md) | Concluído |

## Segurança (estrutura) - ★★★★★

Critérios satisfeitos:

- Documento canónico [`SEGURANCA.md`](SEGURANCA.md) com zonas de confiança, princípios fail-closed e superfícies de ataque
- Segredos isolados (`secrets/`, `.env` gitignored) com script de geração e checklist em [`production-secrets.md`](production-secrets.md)
- Auth em todas as superfícies expostas (API, vm-agent, credenciais guest)
- Uploads sanitizados (backend + vm-agent) com testes automatizados
- Sandbox isolada (rede, snapshot, drivers documentados; `stub` seguro por omissão)
- Integridade de dependências (locks Python, SHA-256 opcional no WPF)
- Validação CI de segurança (pytest + xUnit dedicados)

## Deploy

Checklist e segredos: [`production-secrets.md`](production-secrets.md#checklist-antes-de-deploy) · estrutura: [`SEGURANCA.md` § Checklist](SEGURANCA.md#checklist-estrutural).

Locks Python: `pip install --require-hashes -r backend/requirements.lock` - regenerar com `scripts/ci/compile_python_locks.ps1`.

Testes e contribuição: [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Manutenção futura (não bloqueadores)

- Afinar regras YARA com amostras reais
- Telemetria Sysmon/ETW no vm-agent
- Executar testes `@pytest.mark.integration` em laboratório (`RUN_VM_DRIVER_INTEGRATION=1`) - ver `backend/tests/test_vm_drivers.py`
