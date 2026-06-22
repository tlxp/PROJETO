# Relatório académico

LaTeX do relatório de licenciatura, co-localizado com o código para facilitar entrega e manutenção dos diagramas.

**Versão do software:** `0.1.0` (15 Jun 2026) + alterações em `[Unreleased]` — ver [`CHANGELOG.md`](../CHANGELOG.md).

Índice geral: [`docs/README.md`](../docs/README.md) · diagramas fonte: [`docs/diagrams/`](../docs/diagrams/) · i18n: [`docs/i18n.md`](../docs/i18n.md) · segurança: [`docs/SEGURANCA.md`](../docs/SEGURANCA.md).

## Estrutura

```
relatório/
├── main.tex              # Documento principal (capítulos 1–6 + apêndice)
└── imagens/
    ├── README.md         # Guia de PNGs e render PlantUML
    ├── render_plantuml.py
    ├── logo.png          # Capa
    └── fig-4-*.png       # Diagramas cap. 4 (gerados a partir de docs/diagrams/)
```

| Ficheiro | Função |
|----------|--------|
| `main.tex` | Texto, referências, `\graphicspath{{imagens/}}` |
| `imagens/fig-4-*.png` | Diagramas sincronizados com `docs/diagrams/*.puml` (10 figuras, cap. 4) |
| `imagens/render_plantuml.py` | Gera ou valida PNG (requer Java + `plantuml.jar` local) |
| `imagens/fig-5-*.png` | *(opcional)* Screenshots cap. 5 — o PDF compila sem eles |

## Diagramas (fonte única)

Edite **apenas** [`docs/diagrams/`](../docs/diagrams/). O relatório consome PNG derivados:

```powershell
# Validar alinhamento (CI job diagrams)
python scripts/ci/sync_diagrams_to_report.py --check

# Regenerar PNG (requer plantuml.jar em relatório/imagens/)
python relatório/imagens/render_plantuml.py
```

Mapeamento canónico: [`scripts/ci/diagram_sources.py`](../scripts/ci/diagram_sources.py) · detalhe por figura: [`imagens/README.md`](imagens/README.md).

## Compilar o PDF

Requisitos: distribuição LaTeX (TeX Live, MiKTeX) com `pdflatex` e `biber`/`bibtex` se usar bibliografia.

```powershell
cd relatório
pdflatex main.tex
# Repetir pdflatex (+ biber) conforme avisos de referências cruzadas
pdflatex main.tex
```

> `plantuml.jar` e cópias `.puml` em `relatório/imagens/` **não** são versionados — ver `.gitignore`.

## Relação com o código

| Capítulo | Conteúdo ligado ao repo |
|----------|-------------------------|
| 1 — Introdução | Objetivos, Gemini client-side, contexto académico |
| 2 — Estado da arte | Comparação com sandboxes comerciais e frameworks open-source |
| 3 — Tecnologias | Stack multi-linguagem (Python 3.10+, Node 20, .NET 8, Hyper-V) |
| 4 — Arquitetura | Diagramas em `docs/diagrams/`; routers FastAPI; ADRs em `docs/adr/` |
| 5 — Implementação | `frontend/`, `backend/`, `wpf-gui/`, sandbox A/B, testes e manual |
| 6 — Conclusões | Resultados, limitações e trabalho futuro |
| Segurança | [`docs/SEGURANCA.md`](../docs/SEGURANCA.md), [`SECURITY.md`](../SECURITY.md) |
| Internacionalização | [`docs/i18n.md`](../docs/i18n.md) — WPF + web + fallbacks API |

## Estado da implementação (síntese para revisão do cap. 5)

Funcionalidades que devem reflectir-se no texto do PDF (`main.tex`) e nas capturas `fig-5-*.png`:

### Plataforma e versão

- Projeto em **SemVer `0.1.0`**; evolução contínua documentada em `[Unreleased]` no CHANGELOG.
- **Sem Docker** — deploy manual por componente (backend, frontend, WPF, sandbox Hyper-V).
- Artefatos de runtime em `DATA_DIR` (default `%LOCALAPPDATA%\RatAnalyzer`), fora do repositório Git.

### Internacionalização PT/EN

- **WPF:** `LanguageSelectionView`, `Localization/`, `ui-settings.json`, botão *Idioma*, tema visual **Signal** (obsidian + teal), `LogCatalog`, `ProcessOutputEncoding`.
- **Frontend:** `src/i18n/`, `?lang=`, `localStorage`, `VITE_DEFAULT_LOCALE`, `Accept-Language` em `api.ts`.
- **Backend:** `i18n.py`, `RATANALYZER_LANG`, mensagens de fallback localizadas.

### Backend (FastAPI)

- Entrada `api.py` → `app_factory.py` + `routers/` (`analyze`, `jobs`, `health`, `storage`, `deps`, `schemas`).
- Pipeline estático em `modules/` (static, yara, deobfuscator, decompilers, scoring, report).
- Orquestração dinâmica: `vm_orchestrator.py` + `vm_drivers/` (`stub` default, `hyperv`, `proxmox` experimental).
- `POST /api/analysis/upload_dynamic` — publica relatório VM (Caminho B) no mesmo `jobId`.
- Observabilidade: `/api/health` enriquecido, `/metrics` (Prometheus text em memória), logs com `job_id`, rate limiting de uploads.
- Locks reproduzíveis: `requirements.lock` (hashes), `requirements-dev.lock`, `requirements-ghidra.lock`, `requirements-gui.lock`.
- GUI Tkinter opcional: `backend/gui/` (`rat_analyzer_gui.py`).

### Frontend (React + Vite)

- Rotas: `/`, `/analysis/:jobId`, `/analysis/:jobId/xref` (legados `/resultados`, `/xref`).
- Três painéis: pseudo-C, IL e **relatório** (dividido horizontalmente em estático + VM quando ambos existem no mesmo `jobId`).
- Polling em tempo real via `useAnalysisJob` enquanto a análise na VM decorre.
- Assistente **Gemini** client-side (`gemini-2.0-flash`), API key em `localStorage`.
- Playwright E2E; flags React Router v7 future; testes `FileDropZone`.

### Desktop WPF (`RatAnalyzer.Desktop`)

| Vista | Função |
|-------|--------|
| `LanguageSelectionView` | Escolha PT/EN no primeiro arranque |
| `LoadingView` | Bootstrap + `StartupSequence` |
| `MainDashboardView` | Drop de ficheiros, estática vs comportamental |
| `VmAnalysisWindow` | Log em tempo real do `04-Run-Sample.ps1` |
| `VmGuestCredentialsWindow` | Credenciais guest (PowerShell Direct) |
| `StorageMaintenanceWindow` | Gestão de artefatos via `/api/storage/*` |

- Após análise VM: envia relatório ao backend (`upload_dynamic`) e abre browser no permalink unificado (`?lang=`).
- Caminho B (PowerShell Hyper-V), **não** o driver `hyperv.py` do backend.

### Sandbox Hyper-V — dois caminhos (ADR 001)

| Caminho | Orquestrador | Telemetria |
|---------|--------------|------------|
| **A** | `vm_orchestrator.py` → `vm-agent` HTTP | Básica |
| **B** | WPF / `04-Run-Sample.ps1` | Completa (ficheiros, registry, rede, Sysmon) |
| **stub** | Backend (default) | Nenhuma — valida fluxo sem VM |

> Driver **`proxmox`** é experimental (sem guia, sem CI de integração). Ver [`docs/README.md`](../docs/README.md).

### Regras YARA

- Conjunto **v2.0.0** (`yara_rules/VERSION`): `rat_generic.yar`, `c2_patterns.yar`, `stealer.yar`, `evasion.yar`.

### Outros componentes

- `vm-agent/` — Minimal API .NET 8 na VM (Caminho A).
- `benign-vm-test/` — smoke test inofensivo do pipeline VM.
- `programa/MeuExemplo/` — projeto de exemplo para testes manuais e GUI Tkinter.

### Testes e CI

| Componente | Framework | Testes |
|----------|-----------|--------|
| Backend | pytest + httpx | **84** |
| Frontend | Vitest | **56** |
| Frontend E2E | Playwright | Fluxo upload/análise |
| .NET | xUnit (vm-agent, WPF, benign-vm-test, MeuExemplo) | **54** |
| Diagramas | `sync_diagrams_to_report.py --check` | 10 figuras cap. 4 |

**Jobs CI** (`.github/workflows/ci.yml`): `backend`, `frontend`, `frontend-e2e`, `dotnet`, `ps1-encoding`, `md-docs`, `diagrams`, `powershell`, `security` (gitleaks).

**Qualidade adicional:** Dependabot (pip, npm, github-actions, nuget), pre-commit (`.pre-commit-config.yaml`), `pip-audit`, `npm audit`, cobertura pytest/vitest.

Testes de integração VM (`hyperv`/`proxmox`): opt-in via `RUN_VM_DRIVER_INTEGRATION=1` — **não** fazem parte do CI padrão.

### ADRs (decisões arquiteturais)

| ADR | Título |
|-----|--------|
| [001](../docs/adr/001-dual-dynamic-paths.md) | Dois caminhos dinâmicos (A: vm-agent, B: PowerShell) |
| [002](../docs/adr/002-api-routers.md) | Backend modularizado em routers |
| [003](../docs/adr/003-observability-minimal.md) | Observabilidade mínima sem stack externa |

### Roadmap pendente (README principal)

- IDA (Ghidra já integrado), deobfuscação avançada, telemetria Sysmon/ETW no vm-agent, mais formatos, base de assinaturas, análise de rede C&C.

---

Atualize `main.tex` e screenshots `fig-5-*.png` quando o layout da UI mudar significativamente. O cap. 3 ainda referencia «34+ testes Vitest» — o valor actual é **56** (ver tabela de testes acima).
