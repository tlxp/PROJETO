# Imagens do relatório

Pasta do `main.tex` (`\graphicspath{{imagens/}}`). Visão geral: [`../README.md`](../README.md).

> O relatório académico (`relatório/main.tex`) vive no mesmo repositório que o código
> para facilitar a entrega da licenciatura. A **fonte técnica** dos diagramas do cap. 4 está em
> [`docs/diagrams/`](../../docs/diagrams/) — edite apenas lá; esta pasta guarda os PNG gerados.

## Capítulo 4 — diagramas PlantUML

Fonte: [`docs/diagrams/`](../../docs/diagrams/) · mapeamento em [`scripts/ci/diagram_sources.py`](../../scripts/ci/diagram_sources.py).

| Fonte `.puml` | PNG nesta pasta | Tema |
|---------------|-----------------|------|
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

Não existem cópias `.puml` aqui — apenas estes PNG e `logo.png` (capa).

### Gerar ou validar

```powershell
cd relatório\imagens
python render_plantuml.py              # gerar (requer plantuml.jar + Java)
python render_plantuml.py --check      # validar timestamps PNG vs fonte
python ..\..\scripts\ci\sync_diagrams_to_report.py --check   # equivalente CI (job diagrams)
```

O job **`diagrams`** no CI falha se algum PNG estiver em falta ou desatualizado face a `docs/diagrams/`.

## Capítulo 5 — screenshots (opcional)

O PDF compila sem estes ficheiros (`\IfFileExists` no `main.tex`). Quando existirem, devem reflectir o **layout actual** da aplicação.

| Ficheiro | Conteúdo sugerido | Notas para captura |
|----------|-------------------|-------------------|
| `fig-5-1-web-upload.png` | Zona de upload (*Drop & Analyze*) | UI bilíngue (PT ou EN); tema escuro Tailwind |
| `fig-5-2-web-results.png` | Resultados com score e painéis de código | Mostrar coluna **relatório dividida** (estático + VM) quando ambos existem no mesmo `jobId`; permalink `/analysis/{jobId}?lang=…` |
| `fig-5-3-wpf-dashboard.png` | Ecrã principal WPF | Tema **Signal** (obsidian + teal); botão *Idioma* visível |
| `fig-5-4-hyperv-vm.png` | Hyper-V Manager | VM `MalwareSandbox`, snapshot `CleanState` |

### Elementos da UI a documentar nas capturas

- **Web:** três painéis (pseudo-C, IL, relatório); ícone Gemini no painel C; seletor de idioma ou URL com `?lang=en`.
- **WPF:** `MainDashboardView` com drop zone; opcionalmente `VmAnalysisWindow` (log do `04-Run-Sample.ps1`) ou `StorageMaintenanceWindow` (manutenção via API).
- **Sandbox:** estado da VM após `01-Setup-MalwareSandbox.ps1`; base `D:\PROJETOVM` (`PROJETOVM_BasePath`).

## Outros ficheiros nesta pasta

| Ficheiro | Função |
|----------|--------|
| `logo.png` | Logótipo na capa do PDF |
| `render_plantuml.py` | Script de render/validação (invoca `diagram_sources.py`) |
| `plantuml.jar` | *(local, gitignored)* — download manual para regenerar PNG |

Detalhe técnico dos diagramas: [`docs/diagrams/README.md`](../../docs/diagrams/README.md).
