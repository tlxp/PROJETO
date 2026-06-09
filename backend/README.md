# Backend — RAT Analyzer

API **FastAPI** e pipeline de análise de malware (estática + orquestração da análise dinâmica). Pode
ser usado como **servidor** (web/desktop) ou via **CLI**. Para a visão geral do projeto, ver o
[README principal](../README.md).

## Requisitos

- **Python 3.10+**
- Dependências em [`requirements.txt`](requirements.txt) (`pip install -r requirements.txt`)
- **YARA** instalado no sistema (para o scanner) — opcional, mas recomendado
- **Ghidra 12+** + `GHIDRA_INSTALL_DIR` (pseudo-C de binários nativos) — opcional
- **.NET SDK** (descompilação .NET via ILSpy CLI) — opcional

## Execução

### Servidor (API)

```bash
cd backend
pip install -r requirements.txt
uvicorn api:app --reload --port 8000
```

### CLI

```bash
python rat_analyzer.py caminho/para/ficheiro.exe -o reports/ -v
```

### GUI Python (opcional, fluxos .NET)

```bash
python rat_analyzer_gui.py     # arrastar .cs, compilar e analisar o .exe/.dll
```

### Worker de fila (opcional)

Com `REDIS_URL` definido, os jobs correm fora do processo da API (RQ); sem ele, correm em threads locais.

```bash
set REDIS_URL=redis://localhost:6379/0   # Windows
python worker.py
```

## Endpoints principais

| Método | Rota | Descrição |
|--------|------|-----------|
| `POST` | `/api/analyze` | Análise estática (resposta única). |
| `POST` | `/api/analyze_stream` | Análise estática em streaming (NDJSON: logs + resultado). |
| `POST` | `/api/analysis?analysis_type=static\|dynamic\|both` | Cria um job na pipeline. |
| `POST` | `/api/analysis/upload_static` | Publica resultado estático calculado noutro processo no mesmo `job_id`. |
| `GET`  | `/api/analysis/{job_id}` | Estado e artefactos de um job. |
| `GET`  | `/api/analysis/{job_id}/artifacts/obfuscated_snippets` | Excertos ofuscados (texto). |
| `GET`  | `/api/analyses` | Lista de jobs recentes. |
| `GET`  | `/api/health` | Healthcheck. |
| `GET`  | `/api/storage/estimate` · `POST /api/storage/{cleanup,archive,purge}` | Gestão de armazenamento. |

## Estrutura

```
backend/
├── api.py                  # Endpoints FastAPI
├── analysis_jobs.py        # Jobs static | dynamic | both
├── rat_analyzer.py         # Entrada da análise estática (CLI e biblioteca)
├── rat_analyzer_gui.py     # GUI Python (Tkinter + windnd)
├── vm_orchestrator.py      # Orquestração da análise dinâmica (escolhe o driver)
├── config.py               # Configuração central (paths, DATA_DIR, limites)
├── job_store.py            # Persistência de jobs (SQLite)
├── task_queue.py           # Abstração de fila (RQ/Redis ou threads locais)
├── worker.py               # Worker RQ (modo fila)
├── storage_maintenance.py  # Estimativa/limpeza/arquivo/purga de artefactos
├── artifact_naming.py      # Convenções de nomes de artefactos
├── pipeline_version.py     # Versão da pipeline (cache/compatibilidade)
├── clean.py                # Limpeza de caches e artefactos gerados
├── modules/                # Analisadores (ver abaixo)
├── vm_drivers/             # Drivers da análise dinâmica (base, stub, hyperv, proxmox)
├── scripts/                # Utilitários (ex.: check_job_snippets.py)
└── tests/                  # Testes (pytest)
```

### `modules/`

| Módulo | Função |
|--------|--------|
| `static_analyzer.py` | Imports/funções suspeitas, strings C&C, evasão, entropia e packers (PE). |
| `yara_scanner.py` | Compila e aplica regras YARA de `yara_rules/`. |
| `deobfuscator.py` | Deteta XOR, descodifica Base64, identifica ofuscação. |
| `dotnet_decompiler.py` | Descompilação .NET (ILSpy) para C#/IL. |
| `ghidra_decompiler.py` | Pseudo-C de binários nativos (Ghidra). |
| `native_disassembly.py` | Apoio à desmontagem nativa. |
| `obfuscation_snippet_extractor.py` | Extração de excertos ofuscados (limitada por `config.py`). |
| `pseudo_c_highlighter.py` | Realce de indicadores no pseudo-C. |
| `risk_scorer.py` | Score de risco agregado (ver README principal). |
| `report_generator.py` | Geração do relatório final. |

### `vm_drivers/`

Padrão de plugin: `base.py` define a interface e cada driver implementa-a. Selecionado por
`SANDBOX_VM_DRIVER` (`stub` por defeito, seguro). Ver [`docs/sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md).

## Configuração e dados

Os **artefactos de runtime não são versionados**. Por defeito ficam em `%LOCALAPPDATA%\RatAnalyzer`
(`DATA_DIR`), com override via `RATANALYZER_DATA_DIR`. Inclui `reports/`, `decompiled/`, `sandbox_jobs/`
e a base de dados SQLite `analysis.db`. Ver [`config.py`](config.py).

Variáveis de ambiente relevantes:

| Variável | Efeito |
|----------|--------|
| `RATANALYZER_DATA_DIR` | Override do diretório base de dados/artefactos. |
| `GHIDRA_INSTALL_DIR` | Caminho do Ghidra (ativa pseudo-C nativo). |
| `REDIS_URL` | Ativa o modo de fila (RQ); sem ela, jobs em threads locais. |
| `SANDBOX_VM_DRIVER` | Driver da análise dinâmica (`stub`/`hyperv`/`proxmox`). |

(Variáveis específicas da sandbox dinâmica em [`docs/sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md).)

## Testes

```bash
cd backend
python -m pytest
```

## Limpeza

```bash
python clean.py              # use --dry-run para simular
```

Remove `__pycache__/`, `.pytest_cache`, `*.pyc`/`*.pyo`, `bin/`, `obj/` e `decompiled/`. Não apaga código
fonte nem relatórios.
