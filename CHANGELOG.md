# Changelog

Formato inspirado em [Keep a Changelog](https://keepachangelog.com/).
Versionamento [SemVer](https://semver.org/) a partir de `0.1.0` (projeto académico - sem releases GitHub formais).

## [Unreleased]

### Added
- `POST /api/analysis/upload_dynamic` — publica relatório VM (Caminho B) no backend; associa ao mesmo `jobId` da análise estática.
- Frontend: coluna *Relatório* dividida horizontalmente (estático + VM) e polling em tempo real em `/analysis/{jobId}`.
- WPF: após transferência do relatório da VM, envia para o backend e abre o browser no permalink unificado.
- Job CI `diagrams` - valida PNG do relatório vs `docs/diagrams/`.
- Projeto exemplo `programa/MeuExemplo/` para GUI Tkinter e testes manuais.
- Testes de driver VM: stub unitário + integração `hyperv`/`proxmox` (opt-in via `RUN_VM_DRIVER_INTEGRATION=1`).
- Diagrama Mermaid de decisão (Caminho A vs B) no README principal.

### Changed
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
