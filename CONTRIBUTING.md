# Como contribuir

Obrigado por interesse no **RAT Analyzer**. Este guia resume convenções para avaliadores, colegas de projeto e contribuidores externos.

## Antes de começar

1. Leia o [README principal](README.md) e o índice em [`docs/README.md`](docs/README.md).
2. Para análise dinâmica, escolha o caminho correto - tabela em [README § Análise dinâmica](README.md#análise-dinâmica-sandbox).
3. **Nunca** commite segredos (`secrets/`, `.env`, passwords de VM). Use [`docs/production-secrets.md`](docs/production-secrets.md).

## Ambiente de desenvolvimento

```bash
# Backend
cd backend
pip install --require-hashes -r requirements.lock
pip install --require-hashes -r requirements-dev.lock
python -m pytest tests -q

# Integração VM (opt-in - requer sandbox real):
# RUN_VM_DRIVER_INTEGRATION=1 SANDBOX_VM_DRIVER=hyperv python -m pytest tests/test_vm_drivers.py -m integration -q

# Frontend
cd frontend && npm i && npm run test && npm run build

# .NET (WPF, vm-agent, benign-vm-test)
dotnet build RatAnalyzer.sln -c Release
dotnet test RatAnalyzer.sln -c Release --no-build

# Diagramas (fig-4-* alinhados com docs/diagrams/) - também validado no CI
python scripts/ci/sync_diagrams_to_report.py --check
# Regenerar PNG (requer Java + plantuml.jar em relatório/imagens/):
python relatório/imagens/render_plantuml.py

# Documentação (.md): links internos e ortografia PT
python scripts/ci/check_md_links.py
```

CI completo: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (inclui job `diagrams` para PNG vs fonte).

## Convenções de código

| Área | Convenção |
|------|-----------|
| **Python** | Ver `backend/`; testes com pytest; locks em `requirements*.lock` |
| **TypeScript** | `strict` no frontend; testes Vitest em `frontend/src/test/` |
| **C# / .NET** | Solução `RatAnalyzer.sln`; MVVM no WPF; testes xUnit em `vm-agent/VmAgent.Tests/`, `wpf-gui/RatAnalyzer.Desktop.Tests/` e `benign-vm-test/BenignVmTest.Tests/` |
| **PowerShell** | UTF-8 BOM, CRLF, mensagens em PT - [`docs/ps1-scripts.md`](docs/ps1-scripts.md) |
| **Documentação** | Markdown em PT; ortografia atual (ex.: `atual`, `ativa`, `artefato`, `seção`) |

## Documentação

- Alterações de arquitetura: atualizar README do componente + [`docs/README.md`](docs/README.md) se aplicável.
- Diagramas: editar **apenas** [`docs/diagrams/`](docs/diagrams/). Mapeamento canónico em
  [`scripts/ci/diagram_sources.py`](scripts/ci/diagram_sources.py) (`docs/diagrams/` → `relatório/imagens/fig-4-*.png`).
  Validar: `python scripts/ci/sync_diagrams_to_report.py --check` (CI job `diagrams`). Regenerar PNG:
  `python relatório/imagens/render_plantuml.py` (requer `plantuml.jar`).
- Desenhos obsoletos: mover para [`docs/archive/`](docs/archive/README.md) com aviso `⚠ Documento arquivado` no topo (a pasta pode estar vazia até haver documentos a arquivar).
- Validação local: `python scripts/ci/check_md_links.py` (links, ortografia legada, H1 único, espaços finais).

## Sandbox e segurança

- **Arquitetura:** [`docs/SEGURANCA.md`](docs/SEGURANCA.md) - documento canónico (zonas, auth, checklist).
- Análise de **malware real** apenas em VM isolada (Hyper-V, sem internet).
- Não exponha o backend nem o vm-agent à WAN sem autenticação.
- Segredos: [`docs/production-secrets.md`](docs/production-secrets.md) - **nunca** commitar `secrets/` ou `.env`.
- Problemas na sandbox: [`scripts/hyperv-sandbox/TROUBLESHOOTING.md`](scripts/hyperv-sandbox/TROUBLESHOOTING.md).
- FAQ: [`docs/faq.md`](docs/faq.md).
- Amostras e relatórios ficam em `DATA_DIR` (ver `backend/config.py`) - não versionar.

## Sugestões e bugs

Descreva o problema com: SO, passos para reproduzir, logs relevantes e componente (backend / frontend / WPF / sandbox). Para alterações de código, inclua testes quando fizer sentido.

## Licença

Contribuições aceites seguem a [licença MIT](LICENSE) do projeto.
