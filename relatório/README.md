# Relatório académico

LaTeX do relatório de licenciatura, co-localizado com o código para facilitar entrega e manutenção dos diagramas.

Índice geral: [`docs/README.md`](../docs/README.md) · diagramas fonte: [`docs/diagrams/`](../docs/diagrams/).

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
| 4 — Arquitetura | Diagramas em `docs/diagrams/` |
| 5 — Implementação | `frontend/`, `backend/`, `wpf-gui/`, sandbox; job unificado estático+VM via `upload_dynamic` |
| Segurança | [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) |
