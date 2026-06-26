# GUI Python (Tkinter) — **DEPRECATED (legacy)**

> **Estado:** deprecada. Mantida para compatibilidade; **não** recebe novas funcionalidades.
> Remoção planeada numa versão futura, após período de aviso.

Interface gráfica **leve** para análise rápida sem instalar o WPF nem o frontend web.
Substitutos recomendados: **frontend web** e **desktop WPF** (ver tabela abaixo).

## Substitutos recomendados

| Interface | Pasta | Melhor para |
|-----------|-------|-------------|
| **Frontend web** | [`frontend/`](../../frontend/) | Análise completa, relatórios, pseudo-C, IL, xrefs, jobs unificados |
| **Desktop WPF** | [`wpf-gui/`](../../wpf-gui/) | Desktop integrado, análise estática/dinâmica, sandbox Hyper-V (Caminho B) |
| ~~GUI Tkinter~~ *(legacy)* | esta pasta | Apenas quem já depende do fluxo local sem backend FastAPI |

A GUI Tkinter **não** substitui o WPF nem a webapp. Os fluxos principais do projeto
(análise estática via API, jobs, relatórios ricos, análise dinâmica) estão cobertos
pelo **frontend React** e pelo **WPF**.

### O que a Tkinter ainda faz (e os substitutos não replicam exactamente)

| Fluxo Tkinter | Web / WPF |
|---------------|-----------|
| Análise estática **local** (`rat_analyzer.py` in-process, sem `uvicorn`) | Requerem backend FastAPI a correr |
| Arrastar `.cs` → `dotnet publish` → analisar `.exe`/`.dll` na mesma janela | WPF: seleccionar `.exe`/`.dll` já compilado; compilar `.cs` via CLI/`dotnet` à parte |
| Visualização básica de código/relatório em janelas Tkinter | Relatórios completos no browser ou no WPF |

Se não precisa destes atalhos de laboratório, **migre para web ou WPF**.

## Estrutura

| Ficheiro | Função |
|----------|--------|
| [`rat_analyzer_gui.py`](../rat_analyzer_gui.py) | **Wrapper fino** — apenas `from gui.tkinter_app import main` |
| [`tkinter_app.py`](tkinter_app.py) | Implementação Tkinter (~550 linhas) |

## Requisitos (se ainda usar)

- Python 3.10+ com dependências do backend (`requirements.lock`)
- Extra GUI: `pip install --require-hashes -r requirements-gui.lock` (`windnd` para drag-and-drop no Windows)
- `.NET SDK` — apenas se arrastar ficheiros `.cs` (compila via `dotnet publish`)

## Execução (legacy)

```bash
cd backend
pip install --require-hashes -r requirements.lock
pip install --require-hashes -r requirements-gui.lock   # opcional: drag-and-drop
python rat_analyzer_gui.py
```

## Pasta `programa/`

Projetos `.cs` de exemplo para testar o fluxo *arrastar .cs → compilar → analisar* podem ser
colocados em [`../../programa/`](../../programa/). Os artefatos `bin/` e `obj/` dessa pasta são
limpos por `python clean.py`. O WPF e a webapp também podem analisar os binários gerados.
