# Diagramas PlantUML

**Fonte única:** `docs/diagrams/*.puml` → PNG em `relatório/imagens/fig-4-*.png` (LaTeX).

| Fonte | PNG no relatório |
|-------|------------------|
| `analysis-usecase.puml` | `fig-4-1-usecase.png` |
| `analysis-activity-static.puml` | `fig-4-2-activity-static.png` |
| `analysis-activity-dynamic.puml` | `fig-4-3-activity-dynamic.png` |
| `analysis-architecture.puml` | `fig-4-4-architecture.png` |
| `analysis-sequence-overview.puml` | `fig-4-5-sequence-overview.png` |

Não existem cópias `.puml` no relatório - apenas estes ficheiros e os PNG gerados.

```powershell
cd relatório\imagens
python render_plantuml.py          # gerar PNG (plantuml.jar)
python render_plantuml.py --check  # validar PNG vs fonte
# Equivalente no CI / validação local:
python scripts/ci/sync_diagrams_to_report.py --check
```

Índice: [`docs/README.md`](../README.md).
