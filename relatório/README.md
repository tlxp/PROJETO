# Relatório académico

LaTeX do relatório de licenciatura, co-localizado com o código para facilitar entrega e manutenção dos diagramas.

Índice geral: [`docs/README.md`](../docs/README.md) · diagramas fonte: [`docs/diagrams/`](../docs/diagrams/) · i18n: [`docs/i18n.md`](../docs/i18n.md).

## Estrutura

```
relatório/
├── main.tex              # Documento principal (capítulos 1–6)
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

Mapeamento canónico: [`scripts/ci/diagram_sources.py`](../scripts/ci/diagram_sources.py).

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
| 4 — Arquitetura | Diagramas em `docs/diagrams/`; routers FastAPI; ADRs em `docs/adr/` |
| 5 — Implementação | `frontend/` (i18n, Gemini), `backend/` (`routers/`, `i18n.py`), `wpf-gui/` (localização, tema Signal, bootstrap); job unificado estático+VM via `upload_dynamic` |
| Segurança | [`docs/SEGURANCA.md`](../docs/SEGURANCA.md), [`SECURITY.md`](../SECURITY.md) |
| Internacionalização | [`docs/i18n.md`](../docs/i18n.md) — WPF + web + fallbacks API |

## Estado da implementação (síntese para revisão do cap. 5)

Funcionalidades recentes que devem reflectir-se no texto do PDF ao recompilar:

- Interface **bilíngue PT/EN** (WPF, SPA React, mensagens de fallback da API).
- WPF: ecrã de idioma no primeiro arranque, `Localization/`, logs de arranque traduzidos, tema visual renovado.
- Backend: modularização `app_factory.py` + `routers/`; observabilidade (`/metrics`, rate limit); `i18n.py`.
- Frontend: módulo `src/i18n/`; Playwright E2E; coluna relatório estático + VM no mesmo `jobId`.
- CI: 84 pytest, 56 Vitest, 54 xUnit, E2E, cobertura, `pip-audit`, `gitleaks`, validação de diagramas.

Atualize `main.tex` e screenshots `fig-5-*.png` quando o layout da UI mudar significativamente.
