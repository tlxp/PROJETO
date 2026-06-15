# GUI Python opcional (Tkinter)

Interface gráfica **leve** para análise rápida sem instalar o WPF nem o frontend web.

## Quando usar

| Interface | Melhor para |
|-----------|-------------|
| **Frontend web** (`frontend/`) | Análise completa, relatórios, pseudo-C, IL |
| **WPF** (`wpf-gui/`) | Desktop integrado, sandbox Hyper-V (Caminho B) |
| **GUI Tkinter** (esta pasta) | Arrastar `.cs` (compilar + analisar) ou `.exe`/`.dll` diretamente, sem Node nem .NET WPF |

A GUI Tkinter **não** substitui o WPF nem a webapp - é um atalho opcional para laboratório e testes locais.

## Requisitos

- Python 3.10+ com dependências do backend (`requirements.lock`)
- Extra GUI: `pip install --require-hashes -r requirements-gui.lock` (`windnd` para drag-and-drop no Windows)
- `.NET SDK` - apenas se arrastar ficheiros `.cs` (compila via `dotnet publish`)

## Execução

```bash
cd backend
pip install --require-hashes -r requirements.lock
pip install --require-hashes -r requirements-gui.lock   # opcional: drag-and-drop
python rat_analyzer_gui.py
```

Implementação: [`tkinter_app.py`](tkinter_app.py).

## Pasta `programa/`

Projetos `.cs` de exemplo para testar o fluxo *arrastar .cs → compilar → analisar* podem ser colocados em [`../../programa/`](../../programa/). Os artefatos `bin/` e `obj/` dessa pasta são limpos por `python clean.py`.
