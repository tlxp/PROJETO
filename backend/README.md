# Backend - RAT Analyzer

API **FastAPI** e pipeline de análise de malware (estática + orquestração da análise dinâmica). Pode
ser usado como **servidor** (web/desktop) ou via **CLI**. Para a visão geral do projeto, ver o
[README principal](../README.md).

## Requisitos

- **Python 3.10+**
- Dependências principais: [`requirements.lock`](requirements.lock) (`pip install --require-hashes -r requirements.lock`)
- Fonte editável: [`requirements.txt`](requirements.txt) - regenerar locks com `scripts/ci/compile_python_locks.ps1`
- Extra Ghidra/pseudo-C: [`requirements-ghidra.lock`](requirements-ghidra.lock)
- GUI Python opcional: [`requirements-gui.lock`](requirements-gui.lock) (`windnd` para drag-and-drop)
- Desenvolvimento/testes: [`requirements-dev.lock`](requirements-dev.lock) (`pytest`, `httpx`)
- Regenerar locks: [`scripts/ci/compile_python_locks.ps1`](../scripts/ci/compile_python_locks.ps1)
- **YARA** instalado no sistema (para o scanner) - opcional, mas recomendado
- **Ghidra 12+** + `GHIDRA_INSTALL_DIR` (pseudo-C de binários nativos) - opcional
- **.NET SDK** (descompilação .NET via ILSpy CLI) - opcional

## Execução

### Servidor (API)

Copie [`backend/.env.example`](.env.example) para `backend/.env` ou exporte variáveis no ambiente.

```bash
cd backend
pip install --require-hashes -r requirements.lock
# Opcional: pip install --require-hashes -r requirements-ghidra.lock
uvicorn api:app --reload --port 8000 --host 127.0.0.1
```

> **Segurança:** recomenda-se fazer bind apenas a `127.0.0.1` (default acima). A API analisa
> malware real e expõe endpoints de manutenção; não a exponha diretamente à rede. Defina
> **Produção:** [`docs/production-secrets.md`](../docs/production-secrets.md) - `RATANALYZER_ENV=production` ou `RATANALYZER_REQUIRE_API_TOKEN=1` obriga `RATANALYZER_API_TOKEN` no arranque. Gere valores com `scripts/generate-production-secrets.ps1`.
>
> `RATANALYZER_API_TOKEN` - com a variável ativa, **todos** os uploads (`/api/analyze`, `/api/analysis`)
> e endpoints de storage exigem o header `X-API-Token`.

### CLI

```bash
python rat_analyzer.py caminho/para/ficheiro.exe -o reports/ -v
```

### GUI Python (deprecated / legacy)

> Substitutos: **frontend web** (`frontend/`) ou **desktop WPF** (`wpf-gui/`). Ver [`gui/README.md`](gui/README.md).

```bash
python rat_analyzer_gui.py     # wrapper fino → gui/tkinter_app.py (legacy)
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
| `POST` | `/api/analysis/upload_dynamic` | Publica relatório da VM (Caminho B — WPF/Hyper-V); pode associar ao mesmo `jobId` da análise estática. |
| `GET`  | `/api/analysis/{job_id}` | Estado e artefatos de um job. |
| `GET`  | `/api/analysis/{job_id}/artifacts/obfuscated_snippets` | Excertos ofuscados (texto). |
| `GET`  | `/api/analyses` | Lista de jobs recentes. |
| `GET`  | `/api/health` | Healthcheck enriquecido (DB, YARA, Ghidra, driver VM). |
| `GET`  | `/metrics` | Métricas Prometheus (contadores em memória). |
| `GET`  | `/docs` | Documentação OpenAPI interativa (Swagger). |
| `GET`  | `/api/storage/estimate` · `POST /api/storage/{cleanup,archive,purge}` | Gestão de armazenamento. |

## Estrutura

```
backend/
├── api.py                  # Entrada uvicorn (app factory)
├── app_factory.py          # Criação FastAPI, middleware, routers
├── routers/                # analyze, jobs, health, storage
├── observability.py        # Métricas /metrics e contexto job_id nos logs
├── i18n.py                 # Mensagens PT/EN (fallbacks de relatório e erros de API)
├── middleware.py           # Rate limit uploads + logging por job_id
├── analysis_jobs.py        # Jobs static | dynamic | both
├── rat_analyzer.py         # Entrada da análise estática (CLI e biblioteca)
├── rat_analyzer_gui.py     # Entrada legacy da GUI Tkinter (wrapper → gui/tkinter_app.py)
├── gui/                    # GUI Tkinter deprecated — ver gui/README.md
├── vm_orchestrator.py      # Orquestração da análise dinâmica (escolhe o driver)
├── config.py               # Configuração central (paths, DATA_DIR, limites)
├── job_store.py            # Persistência de jobs (SQLite)
├── task_queue.py           # Abstração de fila (RQ/Redis ou threads locais)
├── worker.py               # Worker RQ (modo fila)
├── storage_maintenance.py  # Estimativa/limpeza/arquivo/purga de artefatos
├── security_config.py      # Modo produção - exige RATANALYZER_API_TOKEN no arranque
├── upload_security.py      # Sanitização de filenames, validação de job_id, limites de upload
├── artifact_naming.py      # Convenções de nomes de artefatos
├── pipeline_version.py     # Versão da pipeline (cache/compatibilidade)
├── clean.py                # Limpeza de caches e artefatos gerados
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

**Segurança:** [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) · implementação: `security_config.py`, `upload_security.py`.

## Configuração e dados

Os **artefatos de runtime não são versionados**. Por defeito ficam em `%LOCALAPPDATA%\RatAnalyzer`
(`DATA_DIR`), com override via `RATANALYZER_DATA_DIR`. Inclui `reports/`, `decompiled/`, `sandbox_jobs/`
e a base de dados SQLite `analysis.db`. Ver [`config.py`](config.py).

Variáveis de ambiente relevantes:

| Variável | Efeito |
|----------|--------|
| `RATANALYZER_DATA_DIR` | Override do diretório base de dados/artefatos. |
| `RATANALYZER_API_TOKEN` | **(segurança)** Se definido, **todos** os uploads (`/api/analyze`, `/api/analyze_stream`, `/api/analysis`) e endpoints de storage exigem o header `X-API-Token` (comparação em tempo constante; **401** se inválido). Com `RATANALYZER_ENV=production` ou `RATANALYZER_REQUIRE_API_TOKEN=1`, o arranque **falha** sem token - ver `security_config.py`. |
| `RATANALYZER_MAX_UPLOAD_MB` | Limite de tamanho de upload em MB (default **100**). Pedidos acima do limite devolvem **HTTP 413** (verificado via `Content-Length` quando disponível e novamente durante a leitura por chunks). Aplica-se a `/api/analyze`, `/api/analyze_stream` e `/api/analysis`. |
| `RATANALYZER_MAX_WORKERS` | Nº máximo de jobs de análise concorrentes no modo local de threads (default **2**). |
| `RATANALYZER_CORS_ORIGINS` | Lista de origens CORS separadas por vírgulas. Default: `http://localhost:8080,http://127.0.0.1:8080,http://localhost:5173`. |
| `RATANALYZER_LANG` | Idioma dos fallbacks da API (`pt` \| `en`; default `pt`). Lido também de `Accept-Language` nos routers quando aplicável. |
| `GHIDRA_INSTALL_DIR` | Caminho do Ghidra (ativa pseudo-C nativo). |
| `REDIS_URL` | Ativa o modo de fila (RQ); sem ela, jobs em threads locais. |
| `SANDBOX_VM_DRIVER` | Driver da análise dinâmica (`stub`/`hyperv`/`proxmox`). |
| `VM_AGENT_TOKEN` | **(opcional)** Se definido, os drivers `hyperv`/`proxmox` enviam o header `X-Agent-Token` com este valor em todos os pedidos HTTP ao VM agent (health/upload/run/report). O agent .NET valida o mesmo header. |
| `SANDBOX_VM_OP_TIMEOUT_SECONDS` | Timeout (s) dedicado a operações de snapshot/start da VM (default **120**), separado do timeout HTTP de 20s. |

(Variáveis específicas da sandbox dinâmica em [`docs/sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md).)

### Notas de segurança e comportamento de erros

- **Bind local recomendado:** corra a API com `--host 127.0.0.1`. Os endpoints de manutenção são
  destrutivos; proteja-os com `RATANALYZER_API_TOKEN` se a API estiver acessível a outros processos/máquinas.
- **Uploads:** os nomes de ficheiro são sanitizados (rejeitados nomes vazios, com `..`, separadores
  de path ou paths absolutos → **HTTP 400**); o ficheiro é gravado por chunks com limite
  (`RATANALYZER_MAX_UPLOAD_MB` → **HTTP 413** se exceder).
- **`job_id`:** todos os endpoints que recebem `job_id` validam o formato UUID v4 (**400** se inválido,
  **404** se não existir).
- **Erros internos:** respostas 500 devolvem mensagens genéricas; o detalhe fica nos logs do servidor.
- **Purge:** `POST /api/storage/purge` devolve **409** se existirem jobs em execução (`running`).
- **Listagem:** `GET /api/analyses` aplica teto de `limit=200`.

## Testes

```bash
cd backend
pip install --require-hashes -r requirements.lock
pip install --require-hashes -r requirements-dev.lock
python -m pytest tests -q
```

**84 testes** pytest — não dependem de YARA/Ghidra/ILSpy (o pipeline pesado é substituído por mocks) e usam
`RATANALYZER_DATA_DIR` apontado para um diretório temporário. Inclui: API, health, métricas, rate limit, upload security, job reconstruction,
pipeline logging, regras YARA (`test_yara_rules.py`). Cobertura mínima: `pytest --cov` (ver `.coveragerc`, threshold 45%).

## Limpeza

```bash
python clean.py              # use --dry-run para simular
```

Remove `__pycache__/`, `.pytest_cache` (em todo o repo), `*.pyc`/`*.pyo`, `programa/**/bin` e `programa/**/obj`,
decompilados em `DATA_DIR` e legado `decompiled/` na raiz. **Não** apaga código fonte nem relatórios em
`DATA_DIR/reports/`.

Índice: [`docs/README.md`](../docs/README.md).
