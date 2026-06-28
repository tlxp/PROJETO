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

## Capítulo 5 — screenshots (obrigatórios para entrega)

Coloque os PNG nesta pasta. O `main.tex` mostra caixas placeholder até os ficheiros existirem.

| Ficheiro | Como capturar |
|----------|---------------|
| `fig-5-1-web-upload.png` | Ecrã inicial com seletor Estática / Dinâmica / Ambas; `?lang=pt` |
| `fig-5-2-web-results.png` | Resultados após análise; permalink `/analysis/{jobId}`; coluna relatório dividida se estático + VM |
| `fig-5-3-wpf-dashboard.png` | `dotnet run --project wpf-gui` (admin) → `MainDashboardView` com tema Signal (obsidian + teal) e botão *Idioma* |
| `fig-5-4-hyperv-vm.png` | Hyper-V Manager → VM `MalwareSandbox` em execução ou parada, snapshot `CleanState` visível no painel Checkpoints |

### Checklist antes de compilar o PDF final

- [ ] `logo.png` na capa (UBI ou identidade visual do projecto)
- [ ] `fig-5-1` a `fig-5-4` capturados com resolução ≥ 1920 px de largura
- [ ] Texto legível nas capturas (zoom 100--125 % no browser)
- [ ] Sem tokens API, passwords ou dados sensíveis visíveis

| Ficheiro | Conteúdo sugerido | Notas para captura |
|----------|-------------------|-------------------|
| `fig-5-1-web-upload.png` | Zona de upload com modos Estática / Dinâmica / Ambas | UI bilíngue; tema escuro Tailwind |
| `fig-5-2-web-results.png` | Resultados com score e painéis | Relatório dividido (estático + VM) no mesmo `jobId` |
| `fig-5-3-wpf-dashboard.png` | Ecrã principal WPF | Tema **Signal** (obsidian + teal); botão *Idioma* visível |
| `fig-5-4-hyperv-vm.png` | Hyper-V Manager | VM `MalwareSandbox`, snapshot `CleanState` |

### Elementos da UI a documentar nas capturas

- **Web:** três painéis; seletor de modo; ícone Gemini; `?lang=en`.
- **WPF:** `MainDashboardView` com drop zone; opcionalmente `VmAnalysisWindow` (log do `04-Run-Sample.ps1`) ou `StorageMaintenanceWindow` (manutenção via API).
- **Sandbox:** estado da VM após `01-Setup-MalwareSandbox.ps1`; base `D:\PROJETOVM` (`PROJETOVM_BasePath`).

## Outros ficheiros nesta pasta

| Ficheiro | Função |
|----------|--------|
| `logo.png` | Logótipo na capa do PDF |
| `render_plantuml.py` | Script de render/validação (invoca `diagram_sources.py`) |
| `plantuml.jar` | *(local, gitignored)* — download manual para regenerar PNG |

Detalhe técnico dos diagramas: [`docs/diagrams/README.md`](../../docs/diagrams/README.md).
