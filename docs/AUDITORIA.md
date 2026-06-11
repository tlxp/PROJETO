# Auditoria de segurança e qualidade — concluída

Relatório de remediação do **RAT Analyzer** (10–11 Jun 2026). Todos os achados curados da auditoria foram **resolvidos** (100%).

> **Verificação final:** 61 testes pytest · 29 testes Vitest · build .NET Release OK · CI em [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

## Resumo por área

| Área | Principais correções |
|------|----------------------|
| **Backend** | Auth obrigatória em produção (`security_config.py`); uploads sanitizados e limitados; worker RQ reconstruído da DB; `to_thread` no `/api/analyze`; SQLite WAL; logging unificado no pipeline; locks Python com SHA-256 |
| **.NET (WPF + vm-agent)** | `VM_AGENT_TOKEN` obrigatório; bind `127.0.0.1`; MVVM; integridade SHA-256 (Ghidra, ADK, ILSpy, Java); paths via `PROJETOVM_BasePath`; PowerShell com `ArgumentList` |
| **Frontend** | `.gitignore` corrigido; `Index.tsx` refactorizado; TS strict; Error Boundaries; 3 componentes shadcn; `VITE_API_TOKEN` |
| **Sandbox Hyper-V** | Isolamento de rede por run; guest password sem fallback inseguro; `try/finally` em `04-Run-Sample`; host-only em `06-Prepare-GuestDependencies`; firewall host; UTF-8 CI nos `.ps1` |
| **YARA** | Regras v2 com combinações correlacionadas + `test_yara_rules.py` |
| **Infra** | CI (pytest + vitest + dotnet + PS1); `.editorconfig`; `requirements*.lock`; `docs/production-secrets.md` |

## Segurança — checklist de deploy

Ver guia completo: [`production-secrets.md`](production-secrets.md).

- [ ] `RATANALYZER_API_TOKEN` definido; `RATANALYZER_ENV=production` ou `RATANALYZER_REQUIRE_API_TOKEN=1`
- [ ] `VITE_API_TOKEN` igual ao token da API (rebuild do frontend)
- [ ] `VM_AGENT_TOKEN` igual no backend, vm-agent e scripts sandbox
- [ ] `PROJETOVM_GuestPassword` forte; sem `PROJETOVM_ALLOW_INSECURE_DEFAULTS`
- [ ] Backend e frontend apenas em `127.0.0.1` ou rede interna com firewall
- [ ] (Opcional) Hashes de binários: `RATANALYZER_ADK_SETUP_SHA256`, `RATANALYZER_ILSPY_SHA256`, `RATANALYZER_JAVA_EXE_SHA256`

## Dependências reproduzíveis

```powershell
cd backend
pip install --require-hashes -r requirements.lock
pip install --require-hashes -r requirements-dev.lock   # testes
# Extras opcionais:
# pip install --require-hashes -r requirements-ghidra.lock
# pip install --require-hashes -r requirements-gui.lock
```

Regenerar locks após alterar `requirements*.txt`:

```powershell
.\scripts\ci\compile_python_locks.ps1
```

## Testes

```bash
# Backend (61 testes)
pip install --require-hashes -r backend/requirements.lock
pip install --require-hashes -r backend/requirements-dev.lock
python -m pytest backend/tests -q

# Frontend (29 testes)
cd frontend && npm run test && npm run build

# .NET
dotnet build RatAnalyzer.sln -c Release

# Scripts PowerShell (UTF-8)
python scripts/ci/check_ps1_utf8.py
```

## Manutenção contínua (fora do âmbito da auditoria)

Melhorias futuras recomendadas, não bloqueadores:

- Afinar regras YARA por família de malware com amostras reais no laboratório
- Telemetria dinâmica avançada no vm-agent (Sysmon/ETW)
- Testes de integração dos drivers VM (`hyperv`/`proxmox`) com infraestrutura real

## Documentos relacionados

| Documento | Conteúdo |
|-----------|----------|
| [`production-secrets.md`](production-secrets.md) | Segredos e modo produção |
| [`ps1-scripts.md`](ps1-scripts.md) | Política UTF-8 dos scripts PowerShell |
| [`sandbox-hyperv-setup.md`](sandbox-hyperv-setup.md) | Caminho A — VM Agent HTTP |
| [`../scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) | Caminho B — pipeline serial |
| [`../yara_rules/README.md`](../yara_rules/README.md) | Regras YARA v2 |
