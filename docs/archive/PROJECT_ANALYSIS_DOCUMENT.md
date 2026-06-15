# PROJECT_ANALYSIS_DOCUMENT
## RAT Analyzer — Análise Avançada com Engenharia de Software Baseada em Grafos

> **Documento arquivado** — movido para `docs/archive/`. Mantém-se como referência histórica de desenho (grafos, IA, Redis/RQ). **Não** use como manual operacional; consulte [`docs/README.md`](../README.md) e os READMEs de cada componente.

> **Nota:** Várias funcionalidades descritas neste documento já estão implementadas (ex.: pipeline de jobs, análise estática/dinâmica stub, extração de trechos obfuscados, API de artifacts, frontend com links para trechos, integração WPF → browser). O documento mantém-se como referência de desenho e cenários.

---

# 1. Project Overview

## 1.1 Identificação do Projeto

| Atributo | Descrição |
|----------|-----------|
| **Nome** | RAT Analyzer |
| **Tipo de produto** | Ferramenta de análise de malware (análise estática e dinâmica de executáveis/DLLs) |
| **Contexto** | Projeto de licenciatura; ferramenta integrada para deteção de Remote Access Trojans (RATs) |
| **Arquitetura** | Multi-camada: Backend API (Python), Frontend Web (React), Cliente Desktop (WPF .NET 8), Agente em VM (minimal API .NET 8) |

## 1.2 Problema que o Projeto Resolve

O sistema aborda o **domínio da análise de malware**, em particular:

- **Deteção de RATs** em ficheiros executáveis (.exe) e bibliotecas dinâmicas (.dll), e análise de código fonte (.cs) quando aplicável.
- **Análise estática** sem execução: imports suspeitos, strings C&C, técnicas de evasão, YARA, deobfuscação básica, scoring de risco e relatórios.
- **Análise dinâmica (sandbox)** opcional: execução controlada em VM isolada com recolha de comportamento (processos, filesystem, registry, rede).
- **Educação e triagem**: visualização de código descompilado (C#/pseudo-C/IL), relatórios estruturados e (planeado) explicações por IA para funções suspeitas.

## 1.3 Objetivos do Sistema

- Permitir **upload** de amostras (.exe, .dll, .cs) via web ou aplicação desktop.
- Executar **análise estática** (pipeline completo) e opcionalmente **análise dinâmica** em sandbox.
- **Persistir** jobs e resultados (SQLite + ficheiros em `sandbox_jobs/`).
- Apresentar **resultados** numa interface web única: código C/IL, relatório, score, funções suspeitas e (futuro) resumo dinâmico.
- Servir como **ponto único de entrada** na aplicação WPF: drag-and-drop → escolha do tipo de análise → abertura do browser na página de resultados.

## 1.4 Fluxos Principais do Produto

1. **Web (Drop & Analyze):** Utilizador arrasta ficheiro → escolhe modo (estática / dinâmica / ambas) → execução (streaming ou job) → visualização de resultados na mesma aplicação.
2. **Desktop (WPF):** Utilizador arrasta ficheiro na janela → escolhe “Análise estática” ou “Análise comportamental” → backend processa → browser abre na URL de resultados com `jobId`.
3. **Acesso por link:** Abrir `/resultados?jobId=...` ou `/?jobId=...` → frontend faz polling a `/api/analysis/{jobId}` até completed/failed → exibe resultado.

## 1.5 Funcionalidades Centrais

- Upload e validação de ficheiros (.exe, .dll, .cs).
- Pipeline de análise estática (PE, YARA, deobfuscação, descompilação .NET/Ghidra, risk scoring, relatório).
- Pipeline de jobs (estática, dinâmica, ambas) com persistência e histórico.
- API REST para análise síncrona, streaming e gestão de jobs.
- Visualização de código (C, IL, relatório) com syntax highlight, scroll-to-line, funções suspeitas e painéis expansíveis.
- Integração WPF → backend → abertura do frontend no browser com `jobId`.
- (Preparado) Análise dinâmica em VM (stub / Proxmox / Hyper-V) com vm-agent.

---

# 2. Problem Domain Analysis

## 2.1 Domínio do Problema

O domínio é **análise de malware e deteção de RATs**:

- **Entidades:** Amostras (ficheiros), jobs de análise, relatórios estáticos/dinâmicos, indicadores de risco, funções suspeitas, VMs sandbox.
- **Processos:** Upload → triagem (tipo de ficheiro) → análise estática (e opcionalmente dinâmica) → agregação de resultados → apresentação ao utilizador.
- **Regras:** Apenas .exe, .dll, .cs; análise estática sempre disponível; dinâmica depende de driver de sandbox (stub/proxmox/hyperv); resultados guardados por job_id.

## 2.2 Complexidade do Domínio

- **Técnica:** Múltiplas ferramentas (YARA, ILSpy, Ghidra, desmontagem), vários formatos de saída (relatório texto, JSON, pseudo-C, IL).
- **Operacional:** Jobs assíncronos, fila opcional (Redis/RQ), gestão de sandbox (snapshots, timeouts, rede isolada).
- **UX:** Um mesmo resultado pode ser acedido por web (upload direto) ou por desktop (upload via WPF, resultado no browser), e por link partilhável (`jobId`).

## 2.3 Diagrama de Domínio (Conceitual)

```
                    +------------------+
                    |   Utilizador     |
                    +--------+---------+
                             |
         +-------------------+-------------------+
         |                   |                   |
         v                   v                   v
+----------------+  +----------------+  +----------------+
|  Web Frontend  |  |  WPF Desktop   |  |  API (script)  |
+--------+-------+  +--------+-------+  +--------+-------+
         |                   |                   |
         +-------------------+-------------------+
                             |
                             v
                    +------------------+
                    |   Backend API    |
                    |  (FastAPI)       |
                    +--------+---------+
                             |
         +-------------------+-------------------+
         |                   |                   |
         v                   v                   v
+----------------+  +----------------+  +----------------+
| Análise        |  | Job Store      |  | VM Orchestrator|
| Estática       |  | (SQLite)       |  | (Sandbox)      |
+----------------+  +----------------+  +----------------+
         |                   |                   |
         v                   v                   v
+----------------+  +----------------+  +----------------+
| Relatório      |  | sandbox_jobs/  |  | vm-agent       |
| C/IL/YARA      |  | analysis.db    |  | (na VM)        |
+----------------+  +----------------+  +----------------+
```

---

# 3. System Conceptual Graphs

## 3.1 Grafo de Atores

**Nós:** tipos de utilizador, sistemas externos, serviços internos.

**Arestas:** interação (quem usa/quem invoca).

```
                    +------------------+
                    | Analista (Web)   |
                    +--------+---------+
                             | usa
                             v
                    +------------------+
                    | Frontend React   |<-------+ abre no browser (com jobId)
                    +--------+---------+        |
                             | HTTP            |
                             v                 |
                    +------------------+        |
                    | Backend API      |        |
                    +--------+---------+        |
                             |                 |
         +--------------------+----------------+-------------------+
         |                    |                |                   |
         v                    v                v                   |
+----------------+   +----------------+  +----------------+         |
| RAT Analyzer   |   | Job Store      |  | VM Orchestrator |         |
| (estática)     |   | (SQLite)       |  | (stub/proxmox/  |         |
+----------------+   +----------------+  |  hyperv)        |         |
         |                    |         +--------+--------+         |
         |                    |                  |                 |
         v                    v                  v                 |
+----------------+   +----------------+  +----------------+        |
| Módulos        |   | sandbox_jobs/  |  | vm-agent        |        |
| (YARA, Ghidra, |   | analysis.db    |  | (VM guest)     |        |
|  ILSpy, etc.)  |   +----------------+  +----------------+        |
+----------------+                                               |
                                                                  |
+------------------+                                              |
| Utilizador       | arrasta ficheiro, escolhe tipo                |
| (Desktop WPF)    |-----------------------------------------------+
+--------+---------+
         | HTTP (upload, jobId)
         v
+------------------+
| Backend API      |
+------------------+
```

**Resumo dos atores:**

| Ator | Tipo | Interação |
|------|------|-----------|
| Analista (Web) | Utilizador | Usa frontend React: upload, escolhe modo, vê resultados (C, IL, relatório, score). |
| Utilizador Desktop | Utilizador | Usa WPF: drag-and-drop, escolhe estática/dinâmica; abre browser em resultados. |
| Cliente API / Script | Sistema externo | Chama REST: `/api/analyze`, `/api/analysis`, `/api/analysis/{id}`. |
| Backend API | Serviço interno | Orquestra análise estática, jobs, persistência, VM. |
| RAT Analyzer | Serviço interno | Pipeline estático (PE, YARA, decomp, risk, report). |
| Job Store | Serviço interno | SQLite + `sandbox_jobs/` para histórico e payload. |
| VM Orchestrator | Serviço interno | Escolhe driver (stub/proxmox/hyperv), gere VM e vm-agent. |
| vm-agent | Serviço interno (na VM) | Upload, run, report na sandbox. |

## 3.2 Grafo de Funcionalidades

**Nós:** funcionalidades/módulos. **Arestas:** dependência (A depende de B) ou ordem lógica (B depois de A).

```
[Upload & Validação] --> [Triagem PE / .NET / Nativo]
         |
         v
[Descompilação] <-- [.NET: ILSpy]   [Nativo: Ghidra / disassembly]
         |
         v
[Análise Estática] --> [Static Analyzer] --> [YARA] --> [Deobfuscator]
         |                    |                  |
         v                    v                  v
[Risk Scorer] <--------------+------------------+
         |
         v
[Report Generator] --> [last_analysis.json] --> [API Response / Job Result]
         |
         v
[Apresentação Web] <-- [flaggedIndicators / flaggedFunctions]
         |
         v
[CodePanel / Relatório / Score]

--- Pipeline Jobs ---

[POST /api/analysis] --> [create_job] --> [Job Store + sandbox_jobs]
         |
         v
[_run_job] --> [ _run_static ]  e/ou  [ _run_dynamic ]
         |                |                        |
         |                v                        v
         |         [RAT Analyzer]           [VM Orchestrator]
         |                |                        |
         |                v                        v
         +-----------> [update_results] <--- [vm-agent: upload/run/report]
                           |
                           v
                   [GET /api/analysis/{id}]
```

**Dependências lógicas:**

- **Upload** é pré-requisito de toda a análise.
- **Análise estática** pode ser usada sozinha ou em conjunto com dinâmica.
- **Análise dinâmica** depende de VM configurada (stub não executa; proxmox/hyperv executam na VM).
- **Visualização** depende de resultado (estático e/ou dinâmico) já disponível no job ou em memória.

## 3.3 Grafo de Fluxo de Comportamento (Estados e Ações)

Representação **Estado → Ação → Novo Estado** para o fluxo principal (web).

```
[Idle]
  | utilizador carrega ficheiro
  v
[FileLoaded]
  | escolhe modo (static | dynamic | both)
  v
[ReadyToAnalyze]
  | clica "Executar Análise"
  v
[Analyzing]
  | (estática: streaming NDJSON até result; job: polling até completed/failed)
  v
[ResultAvailable]
  | utilizador navega (painéis, funções suspeitas, relatório)
  v
[ViewingResults]
  | clica "Nova Análise"
  v
[Idle]
```

**Variantes:**

- **Modo job (dynamic/both):** `Analyzing` inclui polling a `GET /api/analysis/{jobId}`; transição para `ResultAvailable` quando `status === "completed"` (ou `failed` com mensagem).
- **Acesso por link (`?jobId=xxx`):** estado inicial pode ser `PollingForJob` → quando job disponível → `ResultAvailable`.

---

# 4. Personas

## 4.1 Persona 1 — Ana, Analista de Segurança (Principal)

| Campo | Descrição |
|-------|-----------|
| **Nome** | Ana |
| **Idade** | ~28 anos |
| **Contexto** | Analista de segurança numa empresa de médio porte; analisa amostras suspeitas (exe/dll) para triagem e relatórios. |
| **Objetivos** | Triar amostras rapidamente, obter score de risco e relatório estático; em casos selecionados, executar análise em sandbox e cruzar com estático. |
| **Frustrações** | Ferramentas dispersas (linha de comando, várias UIs); relatórios em texto pouco navegáveis; difícil explicar a gestão o que uma função “suspeita” faz. |
| **Necessidades** | Uma única entrada (web ou desktop), resultado consolidado (código + relatório + score), e possibilidade de partilhar link do resultado. |
| **Nível técnico** | Alto: conhece PE, redes, malware; não quer perder tempo a configurar ferramentas. |
| **Interação** | Preferência por **web**: arrasta ficheiro, escolhe “Apenas estática” ou “Ambas”, lê relatório e código com funções suspeitas destacadas. Usa **desktop** se quiser integrar no fluxo local (ex.: análise a partir de pasta de amostras). |
| **Motivação** | Reduzir tempo de triagem e ter um único sítio para código descompilado + relatório + (futuro) explicação por IA. |

## 4.2 Persona 2 — Rui, Investigador / Estudante (Secundária)

| Campo | Descrição |
|-------|-----------|
| **Nome** | Rui |
| **Idade** | ~24 anos |
| **Contexto** | Mestrado em cibersegurança ou investigador júnior; estuda comportamento de RATs e quer aprender a interpretar código malicioso. |
| **Objetivos** | Ver código descompilado (C#/pseudo-C) e relatório com indicadores; entender que funções/APIs são suspeitas e porquê. |
| **Frustrações** | Falta de contexto educativo nas ferramentas; relatórios técnicos sem “tradução” para decisão. |
| **Necessidades** | Interface clara (C, IL, relatório), navegação por funções suspeitas e (futuro) explicações em linguagem natural. |
| **Nível técnico** | Médio-alto: sabe programar e bases de PE; está a aprender análise de malware. |
| **Interação** | Usa principalmente a **web**: upload, análise estática, explora painéis de código e relatório, segue links para funções suspeitas. |
| **Motivação** | Aprender análise de malware a partir do código real e dos indicadores gerados pelo sistema. |

## 4.3 Persona 3 — Marco, Operador de SOC / Integrador (Secundária)

| Campo | Descrição |
|-------|-----------|
| **Nome** | Marco |
| **Idade** | ~30 anos |
| **Contexto** | SOC ou equipa de operações; precisa de integrar a análise em pipelines (CI, playbooks) ou de consultar resultados via API. |
| **Objetivos** | Submeter amostras por API, obter job_id e resultado (JSON); eventualmente listar histórico de análises. |
| **Frustrações** | Falta de API estável ou documentação clara; resultados só em UI. |
| **Necessidades** | REST bem definido: POST para análise/job, GET para estado e resultado; histórico com paginação. |
| **Nível técnico** | Alto: scripts, PowerShell, Python. |
| **Interação** | Cliente **API**: `POST /api/analysis`, `GET /api/analysis/{job_id}`, `GET /api/analyses`; pode usar frontend apenas para inspeção visual ocasional. |
| **Motivação** | Automatizar triagem e integrar com outros sistemas (SIEM, ticketing). |

---

# 5. Usage Scenarios

## 5.1 Cenário 1 — Triagem Rápida (Web, Só Estática)

- **Contexto:** Ana recebe um .exe suspeito por email e quer triagem rápida.
- **Objetivo:** Obter score de risco e relatório estático sem executar o ficheiro.
- **Passos:** (1) Abre a aplicação web; (2) Arrasta o .exe para a zona de drop; (3) Seleciona “Apenas estática”; (4) Clica “Executar Análise”; (5) Acompanha logs (streaming); (6) Quando termina, lê o relatório e o score; (7) Navega nas funções suspeitas no painel de código.
- **Resultado esperado:** Score (0–100), nível (CRÍTICO/ALTO/…), relatório por categorias e código com indicadores destacados.
- **Falhas/obstáculos:** Ficheiro muito grande ou ofuscado pode demorar; timeout ou erro de descompilação mostrado na UI.

## 5.2 Cenário 2 — Análise Estática + Dinâmica (Web, Job)

- **Contexto:** Ana quer confirmar comportamento em sandbox além da análise estática.
- **Objetivo:** Obter resultado estático e relatório comportamental (processos, rede, etc.).
- **Passos:** (1) Upload do ficheiro na web; (2) Escolhe “Ambas”; (3) “Executar Análise”; (4) Sistema cria job e devolve jobId; (5) Frontend faz polling a `GET /api/analysis/{jobId}`; (6) Quando status = completed, mostra resultado (estático + dynamicSummary); (7) Ana consulta relatório e código.
- **Resultado esperado:** Mesma vista de resultados com secção de resumo dinâmico (quando driver não for stub e vm-agent devolver dados).
- **Falhas/obstáculos:** VM indisponível ou timeout; status “failed” com mensagem; stub não executa realmente o binário.

## 5.3 Cenário 3 — Entrada pelo Desktop e Resultados no Browser (WPF)

- **Contexto:** Ana prefere arrastar o ficheiro a partir do ambiente de trabalho e abrir o resultado no browser.
- **Objetivo:** Usar a aplicação WPF como entrada única e ver resultados na web.
- **Passos:** (1) Abre a aplicação WPF; (2) Arrasta .exe ou .dll para a área de drop; (3) Aparecem opções “Análise estática” e “Análise comportamental”; (4) Clica “Análise estática”; (5) Aplicação envia ficheiro para o backend (job ou upload estático); (6) Obtém jobId e constrói URL `FrontendUrl/resultados?jobId=...`; (7) Abre o browser nessa URL; (8) Frontend faz polling e mostra resultado quando pronto.
- **Resultado esperado:** Browser abre na página de resultados; quando o job estiver completed, aparece o relatório e código.
- **Falhas/obstáculos:** Backend ou frontend não estarem a correr; URL errada (porta 8080 vs 5173); firewall.

## 5.4 Cenário 4 — Acesso por Link Partilhado (jobId)

- **Contexto:** Ana partilha com um colega o link do resultado de uma análise.
- **Objetivo:** O colega abre o link e vê o resultado sem fazer upload.
- **Passos:** (1) Colega abre `https://.../resultados?jobId=xxx` (ou `/?jobId=xxx`); (2) Frontend lê `jobId` da query; (3) Faz polling a `GET /api/analysis/xxx`; (4) Quando status = completed, constrói `AnalysisResult` e renderiza; (5) Colega navega no relatório e código como na análise normal.
- **Resultado esperado:** Mesma experiência de visualização que quem submeteu o job.
- **Falhas/obstáculos:** Job expirado ou apagado; backend diferente; CORS/origins se domínio diferente.

## 5.5 Cenário 5 — Integração por API (Script/CI)

- **Contexto:** Marco quer submeter amostras por script e obter resultado em JSON.
- **Objetivo:** Automatizar submissão e leitura do resultado.
- **Passos:** (1) POST multipart para `/api/analysis?analysis_type=static` (ou dynamic/both); (2) Resposta com `jobId`; (3) Loop: GET `/api/analysis/{jobId}` até status completed ou failed; (4) Parse do payload (staticResult, dynamicResult); (5) Uso em relatório ou encadeamento (ex.: alerta se riskScore > 60).
- **Resultado esperado:** Dados estruturados (report, cCode, ilCode, riskScore, flaggedFunctions, etc.) para consumo programático.
- **Falhas/obstáculos:** Timeout do job; necessidade de autenticação em ambiente produtivo.

---

# 6. User Stories

## 6.1 Upload e Validação

**Como** utilizador (web ou desktop)  
**Quero** carregar um ficheiro .exe, .dll ou .cs  
**Para** o submeter à análise.

- **Critérios de aceitação:** Aceitar drag-and-drop e seleção de ficheiro; validar extensão (.exe, .dll, .cs); mostrar nome do ficheiro e opção de limpar; rejeitar outros tipos com mensagem clara.
- **Dependências técnicas:** FileDropZone (frontend), multipart/form-data (API), validação em backend.
- **Prioridade:** Alta.

## 6.2 Escolha do Tipo de Análise

**Como** utilizador  
**Quero** escolher entre análise apenas estática, apenas dinâmica ou ambas  
**Para** obter o tipo de resultado que preciso.

- **Critérios de aceitação:** Três opções visíveis (estática, dinâmica, ambas); seleção refletida no pedido (query `analysis_type` ou equivalente); em WPF, botões correspondentes após o drop.
- **Dependências técnicas:** Estado no frontend/WPF; API `analysis_type=static|dynamic|both`.
- **Prioridade:** Alta.

## 6.3 Executar Análise Estática (Streaming)

**Como** analista  
**Quero** executar análise estática e ver logs em tempo (quase) real  
**Para** acompanhar o progresso e obter o resultado final na mesma vista.

- **Critérios de aceitação:** POST para `/api/analyze_stream`; consumo de NDJSON (log, result, error); barra de progresso/indicador Ghidra; ao receber `result`, exibir relatório, C, IL, score e funções suspeitas.
- **Dependências técnicas:** StreamingResponse no backend; parser NDJSON no frontend.
- **Prioridade:** Alta.

## 6.4 Executar Análise por Job (Estática/Dinâmica/Ambas)

**Como** utilizador  
**Quero** submeter um job de análise (estática, dinâmica ou ambas) e obter um identificador  
**Para** consultar o resultado quando estiver pronto (incluindo análises longas ou dinâmicas).

- **Critérios de aceitação:** POST `/api/analysis?analysis_type=...` devolve jobId e status; job fica em fila (thread local ou RQ); GET `/api/analysis/{jobId}` devolve status e, quando completed, staticResult/dynamicResult; frontend faz polling até completed/failed.
- **Dependências técnicas:** analysis_jobs, job_store, opcional RQ; frontend polling e `buildAnalysisResultFromJob`.
- **Prioridade:** Alta.

## 6.5 Visualizar Resultados (C, IL, Relatório, Score)

**Como** analista  
**Quero** ver o código descompilado (C/IL), o relatório estruturado e o score de risco  
**Para** triar e interpretar a amostra.

- **Critérios de aceitação:** Três painéis (C, IL, Relatório) com syntax highlight; score e nível visíveis; relatório com categorias navegáveis; painéis expansíveis e scroll-to-line para funções suspeitas.
- **Dependências técnicas:** CodePanel, estado expandedPanel, flaggedIndicators/flaggedFunctions do backend.
- **Prioridade:** Alta.

## 6.6 Navegar por Funções Suspeitas

**Como** analista  
**Quero** saltar para as funções marcadas como suspeitas no código  
**Para** focar rapidamente nas partes relevantes.

- **Critérios de aceitação:** Lista ou botões de funções suspeitas; ao clicar, scroll para o range (startLine–endLine) no painel C; indicadores visuais (marcadores/ranges).
- **Dependências técnicas:** flaggedFunctions com startLine/endLine; CodePanel scrollToLine.
- **Prioridade:** Alta.

## 6.7 Abrir Resultados a Partir do Desktop (WPF)

**Como** utilizador desktop  
**Quero** que, após análise estática iniciada pela aplicação WPF, o browser abra na página de resultados com o jobId  
**Para** ver o relatório na interface web sem copiar links manualmente.

- **Critérios de aceitação:** WPF envia ficheiro ao backend (job ou upload_static); obtém jobId; constrói URL do frontend com `?jobId=...`; abre browser (Process.Start ou equivalente); frontend ao carregar com jobId faz polling e exibe resultado.
- **Dependências técnicas:** MainDashboardView, HttpClient, FrontendUrl configurável.
- **Prioridade:** Alta.

## 6.8 Aceder a Resultado por Link (jobId)

**Como** utilizador  
**Quero** abrir um link com jobId (ex.: partilhado por um colega)  
**Para** ver o resultado dessa análise sem fazer upload.

- **Critérios de aceitação:** Rota suporta query `jobId`; ao carregar, se jobId presente, polling a GET `/api/analysis/{jobId}`; quando completed, mostrar resultado; se failed, mostrar mensagem.
- **Dependências técnicas:** useSearchParams/useLocation, useEffect para polling, buildAnalysisResultFromJob.
- **Prioridade:** Média.

## 6.9 Listar Histórico de Análises

**Como** utilizador ou integrador  
**Quero** listar análises anteriores com paginação  
**Para** reencontrar um job ou auditar o uso.

- **Critérios de aceitação:** GET `/api/analyses?limit=&offset=` devolve lista de jobs (id, analysis_type, status, file_name, created_at, etc.); frontend pode mostrar lista e link para `/resultados?jobId=...`.
- **Dependências técnicas:** job_store.list_jobs; endpoint e UI opcional.
- **Prioridade:** Média.

## 6.10 Publicar Resultado Estático pelo WPF (upload_static)

**Como** aplicação WPF  
**Quero** publicar um resultado de análise estática já concluído (ex.: feito localmente)  
**Para** que o frontend o possa mostrar via GET `/api/analysis/{jobId}`.

- **Critérios de aceitação:** POST `/api/analysis/upload_static` com body JSON (fileName, report, cCode, ilCode, riskScore, riskLevel, flaggedIndicators, flaggedFunctions); backend cria job e grava em job_store; devolve jobId; GET `/api/analysis/{jobId}` devolve esse resultado.
- **Dependências técnicas:** StaticAnalysisUpload, create_job ou equivalente para “só estático já pronto”.
- **Prioridade:** Média (melhora integração WPF quando a análise é feita noutro canal).

## 6.11 Executar Análise Dinâmica em Sandbox Real

**Como** analista  
**Quero** executar a amostra numa VM sandbox (Hyper-V/Proxmox) e obter relatório comportamental  
**Para** complementar a análise estática com comportamento real (processos, rede, etc.).

- **Critérios de aceitação:** Com driver hyperv/proxmox e vm-agent configurados: job type dynamic/both; orquestrador restaura snapshot, inicia VM, envia ficheiro, executa, recolhe report; resultado em dynamicResult; frontend mostra dynamicSummary.
- **Dependências técnicas:** vm_orchestrator, vm-agent, variáveis de ambiente (HYPERV_*, PROXMOX_*, VM_AGENT_BASE_URL).
- **Prioridade:** Média (funcionalidade avançada, depende de infraestrutura).

## 6.12 Explicação por IA de Funções Suspeitas (Futuro)

**Como** analista ou estudante  
**Quero** obter uma explicação em linguagem natural do que uma função suspeita parece fazer  
**Para** aprender e comunicar melhor os achados.

- **Critérios de aceitação:** Na UI, ao selecionar função suspeita, mostrar texto explicativo (ex.: “Possível persistência via registry”, “Chamada C&C”); fonte pode ser IA ou regras.
- **Dependências técnicas:** Backend ou serviço de IA; extensão da API e do frontend.
- **Prioridade:** Baixa (melhoria futura).

---

# 7. Feature Dependency Graph

## 7.1 Grafo de Dependência de Funcionalidades

```
                    +------------------+
                    | Upload & Validate|
                    +--------+---------+
                             |
                             v
                    +------------------+
                    | Choose Analysis  |
                    | Type             |
                    +--------+---------+
                             |
         +--------------------+--------------------+
         |                    |                    |
         v                    v                    v
+----------------+   +----------------+   +----------------+
| Static Only    |   | Dynamic Only   |   | Both           |
| (stream or job)|   | (job)          |   | (job)          |
+--------+-------+   +--------+-------+   +--------+-------+
         |                    |                    |
         v                    v                    v
+----------------+   +----------------+   +----------------+
| Static Pipeline|   | VM Orchestrator|   | Static +       |
| (core)         |   | + vm-agent     |   | Dynamic        |
+--------+-------+   +----------------+   +----------------+
         |                    |                    |
         v                    v                    v
+----------------+   +----------------+   +----------------+
| Job Store /    |   | dynamicResult  |   | Merge results  |
| staticResult   |   |                |   |                |
+--------+-------+   +--------+-------+   +--------+-------+
         |                    |                    |
         +--------------------+--------------------+
                             |
                             v
                    +------------------+
                    | GET /api/analysis/|
                    | {id}             |
                    +--------+---------+
                             |
                             v
                    +------------------+
                    | Result View      |
                    | (C, IL, Report,  |
                    |  Score, Dynamic) |
                    +------------------+
```

## 7.2 Classificação de Features

| Categoria | Funcionalidades |
|-----------|-----------------|
| **MVP (críticas)** | Upload e validação; escolha do tipo de análise; análise estática (streaming ou job); persistência de job e GET por jobId; visualização de resultados (C, IL, relatório, score, funções suspeitas); integração WPF (drop → estática → abrir browser com jobId). |
| **Críticas pós-MVP** | Acesso por link (jobId na query); listar histórico (GET /api/analyses); upload_static para WPF publicar resultado já concluído. |
| **Secundárias** | Análise dinâmica com sandbox real (hyperv/proxmox + vm-agent); melhorias de UX (progresso, erros mais claros). |
| **Futuras** | Explicação por IA de funções suspeitas; mais formatos de exportação; autenticação e quotas. |

## 7.3 Ordem Lógica de Implementação

1. **Núcleo:** Upload → análise estática (síncrona/stream) → resposta com report, cCode, ilCode, score, flaggedIndicators/flaggedFunctions.
2. **Jobs:** Criar job (estática), persistir em SQLite e sandbox_jobs, GET /api/analysis/{id}; frontend polling e vista de resultados a partir de job.
3. **Tipos de análise:** Suporte a analysis_type=dynamic e both; VM stub; integração de dynamicResult na resposta e na UI.
4. **WPF:** Drop → POST job (ou analyze) → obter jobId → abrir browser com URL resultados?jobId=.
5. **Link partilhável:** Suporte a ?jobId= no frontend e fluxo de polling na entrada.
6. **Histórico:** GET /api/analyses e, opcionalmente, lista na UI.
7. **Sandbox real:** Driver hyperv/proxmox, vm-agent com monitorização real; preenchimento de dynamicReport.
8. **Melhorias:** upload_static, IA para funções, etc.

---

# 8. Critical User Flows

## 8.1 Fluxo Principal — Triagem Estática (Web)

```
[Entrada] → [Drop ficheiro] → [Seleção "Apenas estática"] → [Executar Análise]
    → [POST /api/analyze_stream] → [Stream NDJSON: logs + result]
    → [Renderizar resultado: C, IL, Relatório, Score, Funções suspeitas]
    → [Navegação em painéis e funções] → [Saída / Nova Análise]
```

**Pontos de fricção:** Tempo de descompilação (Ghidra) sem feedback claro; ficheiros muito grandes podem exceder limites de payload (summarize_c_code já limita).

## 8.2 Fluxo Principal — Job Estática/Dinâmica (Web)

```
[Entrada] → [Drop ficheiro] → [Seleção "Ambas" ou "Apenas dinâmica"] → [Executar Análise]
    → [POST /api/analysis?analysis_type=both] → [Resposta jobId]
    → [Polling GET /api/analysis/{jobId}] → [status: queued → running → completed]
    → [Renderizar resultado estático + dynamicSummary]
    → [Saída / Nova Análise]
```

**Pontos de fricção:** Espera longa sem estimativa de tempo; falha de VM pode deixar job em “running” ou “failed” sem mensagem detalhada.

## 8.3 Fluxo de Onboarding (Primeira Utilização)

- **Web:** Utilizador abre URL → vê zona de drop e opções (estática/dinâmica/ambas); não há registo; onboarding implícito é “arrastar e escolher”.
- **Desktop:** Arranque da app WPF → (opcional) LoadingPage verifica backend e inicia serviços → MainDashboardView com área de drop; onboarding é “arrastar ficheiro e clicar no tipo de análise”.

**Riscos:** Backend/frontend não iniciados (WPF); portas 8000/5173 ou 8080 incorretas.

## 8.4 Fluxo de Retenção

- Reutilização da mesma sessão para “Nova Análise” (limpar ficheiro e voltar a upload).
- Acesso ao histórico (quando GET /api/analyses estiver exposto na UI) para reabrir resultados antigos.

## 8.5 Fluxo de “Conversão” (WPF → Browser)

- Objetivo: utilizador que prefere desktop não abandonar; “conversão” é abrir o browser no resultado.
- Sequência: Drop no WPF → Análise estática → Abrir browser → Ver resultado na web.
- **Risco de UX:** Se o job ainda estiver a correr, o browser pode mostrar “A carregar…” durante o polling; necessário feedback claro (spinner, mensagem).

## 8.6 Pontos de Fricção e Riscos

| Ponto | Descrição | Mitigação sugerida |
|-------|-----------|---------------------|
| Tempo de análise | Ghidra e análise estática podem demorar | Progresso por streaming; timeout configurável; mensagem “Análise demorada…” |
| Payload grande | pseudo-C muito longo | summarize_c_code (janelas em volta de indicadores); já implementado |
| Job falhado | status failed sem detalhe | Incluir campo error no payload e exibir na UI |
| VM indisponível | dynamic falha | Mensagem clara “Sandbox indisponível”; fallback para só estático |
| Portas/URLs | WPF usa 8080, Vite 5173 | Configuração centralizada (const ou config) no WPF e README |

---

# 9. Architecture Recommendations

## 9.1 Organização Modular (Backend)

- **api.py:** Apenas rotas, validação de entrada e orquestração de chamadas; sem lógica de análise pesada.
- **analysis_jobs.py:** Criação e execução de jobs; delega estática para `RATAnalyzer` e dinâmica para `vm_orchestrator`.
- **rat_analyzer.py:** Orquestrador do pipeline estático; usa módulos em `modules/` (static_analyzer, yara_scanner, deobfuscator, dotnet_decompiler, ghidra_decompiler, risk_scorer, report_generator).
- **job_store.py:** Única camada de persistência para jobs (SQLite); `sandbox_jobs/` como armazenamento de ficheiros por job.

**Recomendação:** Manter esta separação; extrair “serviço de análise estática” (chamada a RATAnalyzer e normalização de resultado) para um módulo `services/static_analysis_service.py` se a API crescer.

## 9.2 Separação de Responsabilidades

| Camada | Responsabilidade |
|--------|------------------|
| **API** | HTTP, CORS, validação de ficheiro, chamada a jobs e a análise síncrona/stream. |
| **Jobs** | Ciclo de vida do job (create, run, update status/results); decisão estático vs dinâmico. |
| **Analyzer** | Pipeline estático completo; não conhece HTTP nem job_id. |
| **VM Orchestrator** | Escolha do driver; snapshot/start/upload/run/report; não conhece detalhes do relatório estático. |
| **Job Store** | CRUD e listagem; paths em disco. |

## 9.3 Serviços e Escalabilidade

- **Monólito atual:** Adequado para MVP e uso interno; um processo uvicorn trata análise estática e jobs (em thread ou RQ).
- **Escalabilidade:** Para muitas análises concorrentes: colocar workers RQ (ou Celery) a processar jobs; API apenas cria job e devolve id; fila Redis. Análise estática pode ser pesada (CPU); considerar limite de workers por máquina.
- **Sandbox:** Um orquestrador por ambiente (Hyper-V ou Proxmox); para múltiplas VMs em paralelo, orquestrador pode manter uma pool de VMs e fila de jobs dinâmicos.

## 9.4 Backend — Estrutura Sugerida (Futuro)

```
backend/
  api/           # Rotas por domínio (analysis, health)
  services/      # Lógica de negócio (static_analysis_service, job_service)
  core/          # config, logging
  modules/       # Analisador (static_analyzer, yara, decompilers, ...)
  vm/            # vm_orchestrator, vm_drivers/
  storage/       # job_store, sandbox_jobs paths
```

## 9.5 Frontend — Estrutura

- **Pages:** Index (landing + resultados), ResultadosPage (wrapper com suporte jobId), NotFound.
- **Componentes:** FileDropZone, CodePanel (C, IL, Relatório), NavLink; UI (shadcn) reutilizável.
- **Estado:** Estado de análise (file, analysisResult, isAnalyzing, logs, error, expandedPanel, scrollToLine) concentrado na página principal; partilhar via props ou contexto se necessário.
- **Recomendação:** Manter estado local enquanto for simples; se surgirem mais fluxos (histórico, favoritos), considerar contexto (React Context ou store leve).

## 9.6 Gestão de Dados

- **Persistência:** SQLite para metadados e resultados (JSON) dos jobs; ficheiros em `sandbox_jobs/{job_id}/` para amostra e `out/` (last_analysis.json, etc.).
- **Consistência:** Job criado em disco e em SQLite na criação; atualizações de status e results em transação; leitura: memória (_JOBS) → SQLite → fallback last_analysis.json.
- **Limpeza:** Política de retenção (ex.: apagar jobs com mais de N dias) ou job de manutenção; opcional endpoint administrativo.

## 9.7 Segurança e Produção

- **Upload:** Limitar tamanho de ficheiro (FastAPI body limit); manter validação de extensão; armazenar em diretório dedicado por job.
- **API:** Em produção: HTTPS, autenticação (JWT ou API key) para POST/GET sensíveis; rate limiting.
- **CORS:** Restringir origins aos domínios do frontend em produção.
- **Sandbox:** VM sem internet; rede interna apenas; reverter snapshot após cada execução.

---

# 10. MVP Definition

## 10.1 Funcionalidades Mínimas para Lançamento

- **Upload:** Ficheiros .exe, .dll, .cs via web (drag-and-drop) e via WPF (drag-and-drop).
- **Análise estática:** Pipeline completo (PE, YARA, deobfuscação, descompilação .NET/Ghidra quando disponível, risk scorer, relatório); exposta como:
  - Síncrona/streaming: POST `/api/analyze` ou `/api/analyze_stream` para uso direto na web.
  - Job: POST `/api/analysis?analysis_type=static`, GET `/api/analysis/{jobId}` para resultado.
- **Persistência:** Job criado e guardado (SQLite + sandbox_jobs); resultado acessível via GET `/api/analysis/{jobId}` (memória → DB → fallback ficheiro).
- **Visualização:** Página web com três painéis (C, IL, Relatório), score, nível de risco, lista de funções suspeitas e navegação (scroll-to-line, indicadores).
- **WPF:** Arrastar ficheiro → escolher “Análise estática” → enviar para backend (job ou análise) → obter jobId → abrir browser em `FrontendUrl/resultados?jobId=...`.
- **Health:** GET `/api/health` para verificação de disponibilidade do backend.

## 10.2 Funcionalidades que Podem Esperar (Pós-MVP)

- Análise dinâmica com sandbox real (Hyper-V/Proxmox + vm-agent completo).
- Listagem de histórico na UI (GET `/api/analyses` já existe; falta UI).
- Acesso por link partilhável (jobId na query) — pode ser considerado MVP se já estiver implementado.
- POST `/api/analysis/upload_static` para WPF publicar resultado estático já concluído.
- Explicação por IA de funções suspeitas.
- Autenticação e autorização.
- Limpeza automática de jobs antigos.

## 10.3 Roadmap Inicial (Sugerido)

| Fase | Conteúdo |
|------|----------|
| **MVP** | Estabilizar fluxo web (upload → estática stream/job → resultados); WPF (drop → estática → abrir browser); GET job por id e polling; documentação de instalação e variáveis. |
| **Pós-MVP 1** | Link partilhável (?jobId=); página ou secção de histórico (lista de análises); mensagens de erro claras (job failed). |
| **Pós-MVP 2** | Análise dinâmica com driver hyperv e vm-agent real (Sysmon/ETW ou equivalente); dynamicSummary e secção na UI. |
| **Futuro** | IA para explicação de funções; mais formatos de exportação; multi-utilizador e quotas. |

---

*Documento gerado no âmbito da análise avançada do projeto RAT Analyzer com engenharia de software baseada em grafos.*
