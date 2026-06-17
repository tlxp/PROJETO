# Imagens do relatório

Pasta do `main.tex` (`\graphicspath{{imagens/}}`). Visão geral: [`../README.md`](../README.md).

> **Nota:** o relatório académico (`relatório/main.tex`) vive no mesmo repositório que o código
> para facilitar a entrega da licenciatura. A **fonte técnica** dos diagramas do cap. 4 está em
> [`docs/diagrams/`](../../docs/diagrams/) — edite apenas lá; esta pasta guarda os PNG gerados.

## Capítulo 4

Fonte: [`docs/diagrams/`](../../docs/diagrams/) · gerar ou validar PNG:

```powershell
cd relatório\imagens
python render_plantuml.py              # gerar (plantuml.jar)
python render_plantuml.py --check      # validar timestamps
python ..\..\scripts\ci\sync_diagrams_to_report.py --check   # equivalente CI
```

## Capítulo 5 (opcional)

`fig-5-1-web-upload.png` · `fig-5-2-web-results.png` · `fig-5-3-wpf-dashboard.png` · `fig-5-4-hyperv-vm.png`

Capturas devem reflectir o layout actual (tema Signal no WPF, UI bilíngue na web). O PDF compila sem eles (`\IfFileExists` no `main.tex`).

Detalhe: [`docs/diagrams/README.md`](../../docs/diagrams/README.md).
