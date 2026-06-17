# Changelog

Formato inspirado em [Keep a Changelog](https://keepachangelog.com/).
Versionamento [SemVer](https://semver.org/) a partir de `0.1.0` (projeto académico - sem releases GitHub formais).

## [Unreleased]

### Added
- **Internacionalização PT/EN** — WPF (`Localization/`), frontend (`src/i18n/`), backend (`i18n.py`); propagação via `RATANALYZER_LANG`, `VITE_DEFAULT_LOCALE`, `Accept-Language` e `?lang=` nas URLs do browser.
- WPF: ecrã de escolha de idioma no primeiro arranque, botão *Idioma* no dashboard, persistência em `ui-settings.json`.
- WPF: tema visual *Signal* (obsidian + teal), logs de arranque localizados (`LogCatalog`), correção de encoding de processos (`ProcessOutputEncoding`).
- Documentação: [`docs/i18n.md`](docs/i18n.md).
- Backend modularizado em `routers/` (`analyze`, `jobs`, `health`, `storage`) + `app_factory.py`.
- Observabilidade: `/api/health` enriquecido, `/metrics` (Prometheus text), logs com `job_id`, rate limiting de uploads.
- CI: cobertura pytest/vitest, `pip-audit`, `npm audit`, `gitleaks`, Playwright E2E.
- Dependabot (`.github/dependabot.yml`), pre-commit (`.pre-commit-config.yaml`), `SECURITY.md`, ADRs em `docs/adr/`.
- `yara_rules/VERSION`, `.nvmrc`, testes `FileDropZone`, flags React Router v7.
- `POST /api/analysis/upload_dynamic` — publica relatório VM (Caminho B) no backend; associa ao mesmo `jobId` da análise estática.
- Frontend: coluna *Relatório* dividida horizontalmente (estático + VM) e polling em tempo real em `/analysis/{jobId}`.
- WPF: após transferência do relatório da VM, envia para o backend e abre o browser no permalink unificado.
- Job CI `diagrams` - valida PNG do relatório vs `docs/diagrams/`.
- Projeto exemplo `programa/MeuExemplo/` para GUI Tkinter e testes manuais.
- Testes de driver VM: stub unitário + integração `hyperv`/`proxmox` (opt-in via `RUN_VM_DRIVER_INTEGRATION=1`).
- Diagrama Mermaid de decisão (Caminho A vs B) no README principal.

### Changed
- WPF: URLs do frontend passam a incluir `?lang=` (`AppConstants.BuildFrontendUrl`); pedidos HTTP ao backend enviam `Accept-Language`.
- Frontend: textos de UI, erros e labels de relatório VM reformatado traduzidos; `api.ts` envia `Accept-Language`.
- `backend/clean.py`: limpa `.pytest_cache` em todo o repo, `programa/**/bin|obj`, `DATA_DIR/decompiled` e legado `decompiled/` na raiz.
- Avisos reforçados para driver `proxmox` (experimental).

## [0.1.0] - 2026-06-15

### Segurança e qualidade
- Auth obrigatória em produção; uploads sanitizados; `VM_AGENT_TOKEN` no vm-agent.
- Documento canónico de segurança: [`docs/SEGURANCA.md`](docs/SEGURANCA.md).
- Sandbox Hyper-V: isolamento de rede, cleanup `try/finally`, UTF-8 CI.
- Regras YARA v2 + testes; CI (pytest, Vitest, xUnit, PowerShell, Markdown, diagramas).

### Documentação
- Índice único em `docs/README.md`; diagramas sem duplicação.
- Fonte única `docs/diagrams/` → PNG `relatório/imagens/fig-4-*.png`.
- Removidos PNG redundantes em `docs/engenharia-de-software/`.

Histórico anterior a `0.1.0`: `git log`.
