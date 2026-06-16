# Diagramas PlantUML

**Fonte única:** `docs/diagrams/*.puml` → PNG em `relatório/imagens/fig-4-*.png` (LaTeX).

| Fonte | PNG no relatório | Tema |
|-------|------------------|------|
| `analysis-usecase.puml` | `fig-4-1-usecase.png` | Casos de uso |
| `analysis-activity-static.puml` | `fig-4-2-activity-static.png` | Pipeline estática |
| `analysis-activity-dynamic.puml` | `fig-4-3-activity-dynamic.png` | Pipeline dinâmica |
| `analysis-architecture.puml` | `fig-4-4-architecture.png` | Arquitetura multi-camada |
| `analysis-sequence-overview.puml` | `fig-4-5-sequence-overview.png` | Sequência integrada |
| `security-trust-zones.puml` | `fig-4-6-security-trust-zones.png` | Zonas de confiança |
| `sandbox-paths-comparison.puml` | `fig-4-7-sandbox-paths.png` | Caminho A vs B |
| `sequence-path-a-vmagent.puml` | `fig-4-8-sequence-path-a.png` | Sequência vm-agent |
| `sequence-path-b-powershell.puml` | `fig-4-9-sequence-path-b.png` | Sequência PsDirect + SHA256 |
| `security-auth-tokens.puml` | `fig-4-10-security-auth.png` | Mapa de autenticação |

Não existem cópias `.puml` no relatório - apenas estes ficheiros e os PNG gerados.

```powershell
cd relatório\imagens
python render_plantuml.py          # gerar PNG (plantuml.jar)
python render_plantuml.py --check  # validar PNG vs fonte
# Equivalente no CI / validação local:
python scripts/ci/sync_diagrams_to_report.py --check
```

Índice: [`docs/README.md`](../README.md).
