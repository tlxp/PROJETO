# Especificações: Arquitetura VM + Docker para o RAT Analyzer

> ⚠ **Documento arquivado** — desenho alternativo (Linux + Docker). **Não está implementado** e **não reflete** o estado atual da codebase. Consulte [`docs/README.md`](../README.md) para documentação vigente.
>
> A análise dinâmica real é **Windows Hyper-V**: **Caminho A** — [`vm-agent/README.md`](../../vm-agent/README.md) + driver `hyperv`; **Caminho B** — [`scripts/hyperv-sandbox/README.md`](../../scripts/hyperv-sandbox/README.md). Para operação, use [`sandbox-hyperv-setup.md`](../sandbox-hyperv-setup.md).

Documento de resposta às perguntas de desenho para tornar o sistema **seguro**, **funcional** e **user-friendly**, alinhado com o projeto actual (webapp drop-n-analyze + backend FastAPI + análise ILSpy/Ghidra/YARA).

---

## 1. Ambiente atual e integração

### 1.1 Onde a webapp corre hoje? E onde pretende que corra no futuro?

- **Hoje**: A webapp (React/Vite) e o backend (FastAPI em `api.py`) podem correr em desenvolvimento no mesmo host (ex.: `npm run dev` + `uvicorn api:app`) ou em deploy separado; o frontend chama `VITE_API_URL` (ex.: `http://localhost:8000`). Não há referência a VM nem Docker na codebase atual.
- **Recomendação (futuro)**:
  - **Webapp (frontend + API “gateway”)**: Continuar a correr **fora** da VM de análise (host, VM de frontend, ou cloud). Assim, a VM de análise pode ser isolada e até sem acesso à internet.
  - **VM de análise**: Dedicada só à análise de ficheiros (orquestrador + Docker + ILSpy/Ghidra). A webapp “fala” com a VM apenas via um único serviço (API HTTP ou fila), nunca expondo o interior da VM.

**Resposta curta**: Webapp no mesmo sítio que hoje (host/cloud); no futuro, a **análise** corre numa **VM dedicada**; a webapp continua fora dessa VM.

---

### 1.2 Como quer que a webapp “fale” com a VM?

- **Recomendação**: **API HTTP na VM** (HTTPS).
  - O backend atual já usa HTTP (FastAPI). O backend pode passar a ser um “gateway” que reencaminha o pedido (ou o ficheiro) para o **orquestrador na VM** via `POST /analyze` (ou equivalente).
  - Vantagens: simples, síncrono ou streaming (como o atual `analyze_stream`), fácil de debugar, sem infraestrutura extra.
  - **Alternativa** (se quiser desacoplar mais): Fila (ex.: RabbitMQ ou Redis Queue) — a webapp envia o job para a fila; um worker na VM consome e devolve o resultado (por callback URL ou websocket). Só vale a pena se houver necessidade de fila, retries e múltiplos workers.

**Resposta curta**: **API HTTP/HTTPS na VM** (um serviço orquestrador que recebe o ficheiro e devolve o resultado/stream). Fila só se for necessário desacoplamento ou alta concorrência.

---

### 1.3 A VM de análise já existe ou será criada do zero? SO e ferramentas?

- O projeto não define isto na codebase; assume-se **criar do zero** ou padronizar uma VM existente.
- **Recomendação**:
  - **SO**: Linux (Ubuntu 22.04 LTS ou Debian 12) para suporte estável a Docker e ferramentas.
  - **Ferramentas**: Docker + Docker Compose; Python 3.11+ para o orquestrador; YARA instalado no host ou na imagem do container; Ghidra (ou pyghidra) e ILSpy/ILSpyCmd dentro do container de análise (ou em imagens separadas por tipo de análise).
  - Documentar no README da VM: instalação de Docker, Docker Compose, variáveis de ambiente (ex.: `GHIDRA_INSTALL_DIR`, `ILSPY_CMD_PATH` se aplicável), e porta do orquestrador.

**Resposta curta**: Assumir **VM criada do zero** com Linux, **Docker + Docker Compose**, Python para o orquestrador, YARA, Ghidra e ILSpy disponíveis no ambiente de análise (idealmente dentro dos containers).

---

## 2. Fluxo de ficheiros e storage

### 2.1 Pasta temporária vs object storage (S3/MinIO)

- **Recomendação**: **Ficheiros em disco** numa pasta dedicada (ex.: `/var/rat-analyzer/uploads` ou `/tmp/rat-uploads`) com quotas e limpeza automática.
  - Mais simples de integrar com o código atual (paths locais, `tempfile.mkdtemp`, etc.).
  - Object storage (S3/MinIO) só se precisar de escalar para várias VMs ou de retenção/auditoria centralizada; acrescenta complexidade e outro ponto de configuração.

**Resposta curta**: **Disco** (path tipo `/var/rat-analyzer/uploads` ou equivalente) com limpeza periódica; object storage só se for requisito explícito.

---

### 2.2 Quem faz o upload para a VM?

- **Recomendação**: **A webapp (através do backend) envia diretamente** o ficheiro para o orquestrador na VM via **HTTP multipart** (como já faz para ` /api/analyze_stream`).
  - O orquestrador na VM recebe o `multipart/form-data`, grava numa pasta temporária com nome único (ex.: UUID), monta essa pasta (read-only) no container, e após a análise apaga o ficheiro.
  - Alternativa “bucket + worker”: a webapp envia para um bucket; um worker na VM copia para a pasta do container. Só recomendável se já existir bucket e se quiser evitar enviar ficheiros grandes pelo gateway.

**Resposta curta**: **Upload direto** (HTTP multipart) da webapp/backend para o **orquestrador na VM**; este grava em disco temporário e monta no container.

---

### 2.3 Tamanho máximo de ficheiro e tempo máximo de análise

- **Recomendação**:
  - **Tamanho máximo**: **50 MB** por ficheiro. Suficiente para a maioria dos .exe/.dll/.cs; evita abuso e reduz risco de OOM. Configurável por variável de ambiente (ex.: `MAX_UPLOAD_MB=50`).
  - **Tempo máximo por análise**: **10 minutos** (600 s). O Ghidra pode ser lento em binários grandes; 10 min permite a maioria das análises sem travar recursos. Timeout aplicado ao `docker run` (ou ao processo de análise) e ao HTTP request no gateway.

**Resposta curta**: **50 MB** máximo por ficheiro; **10 min** tempo máximo por análise; ambos configuráveis.

---

## 3. Containers e análise

### 3.1 Quem cria e destrói o container?

- **Recomendação**: Um **serviço orquestrador** que corre **na VM** (ex.: API em Python/FastAPI ou Node), que:
  - Recebe o pedido da webapp (ficheiro em multipart).
  - Grava o ficheiro numa pasta única (ex.: `uploads/<job_id>/file.exe`).
  - Faz `docker run` (ou `docker compose run`) com essa pasta montada read-only, limites de memória/CPU e timeout.
  - Lê os resultados (relatório, pseudo-C, IL, etc.) da pasta de saída do container (volume ou bind mount).
  - Envia o resultado de volta (streaming NDJSON ou resposta JSON) e **destrói o container** (e opcionalmente a pasta do job) após a resposta.

**Resposta curta**: **Orquestrador na VM** (API em Python/Node) cria e destrói o container por cada análise (ou por cada job da fila).

---

### 3.2 Um ficheiro = um container novo, ou fila + pool reutilizável?

- **Recomendação**: **Um ficheiro = um container novo** (ephemeral).
  - Mais simples, mais seguro (nenhum estado entre análises), e alinhado com “análise 100% offline” e snapshot da VM.
  - Pool reutilizável (containers que processam vários jobs) é mais complexo e exige limpeza de estado entre jobs; só justificado se houver muitos pedidos por segundo e latência de arranque do container for um problema.

**Resposta curta**: **Um container novo por ficheiro**; sem pool reutilizável na primeira versão.

---

### 3.3 ILSpy vs Ghidra: escolha automática ou utilizador? Suportar os dois no mesmo ficheiro?

- **Recomendação**:
  - **Escolha automática por tipo de ficheiro** (e, se necessário, por deteção de PE .NET):
    - `.exe` / `.dll` que são **.NET** (PE com dados .NET): usar **ILSpy** (C#) e, para binários nativos ou híbridos, também **Ghidra** para pseudo-C se configurado.
    - `.exe` / `.dll` **nativos** (sem .NET): usar **Ghidra** para pseudo-C (e análise estática/YARA atual).
    - `.cs`: análise de código fonte (sem ILSpy/Ghidra para decompilação).
  - **User-friendly**: O utilizador **não escolhe** a ferramenta; o sistema decide. Opcionalmente, na UI pode mostrar “Análise .NET (ILSpy)” ou “Análise nativa (Ghidra)” como informação.
  - **Suportar os dois no mesmo ficheiro**: Sim, quando fizer sentido (ex.: binário .NET → ILSpy para C# e assembly; opcionalmente Ghidra para partes nativas se existirem). O backend atual já combina análise estática, YARA, ILSpy e Ghidra; manter essa lógica no container.

**Resposta curta**: **Automático** pela extensão e tipo de ficheiro (.NET vs nativo). **Suportar os dois** no mesmo ficheiro quando aplicável (ex.: .NET + pseudo-C Ghidra); sem escolha manual do utilizador na UI.

---

## 4. Isolamento e hardening

### 4.1 Read-only no container: só working dir read-write?

- **Recomendação**: **Volume read-write mínimo** apenas para o diretório de trabalho (tmp/cache) do processo de análise (ex.: `/workspace` ou `/tmp/analysis`), e **resto read-only** (incluindo a pasta onde está o ficheiro analisado).
  - ILSpy e Ghidra podem precisar de escrever cache/temporários; um único mount read-write pequeno evita falhas e mantém o ficheiro de entrada imutável.
  - Implementação: `--read-only` no `docker run` + `--tmpfs /tmp` ou `-v volume_tmp:/tmp` (ou `-v job_workspace:/workspace`).

**Resposta curta**: **Sim**: ficheiro montado **read-only**; **um volume read-write mínimo** só para working dir (tmp/cache). Resto do container read-only.

---

### 4.2 User não-root no container

- **Recomendação**: **Sim** — correr o processo de análise como **user não-root** (ex.: `--user 1000:1000` ou um user criado na Dockerfile).
  - Reduz impacto de escape do container; as imagens oficiais ou customizadas devem criar um user (ex.: `ratanalyzer`) e usar `USER ratanalyzer` no Dockerfile.

**Resposta curta**: **Sim**: correr como **user não-root** (ex.: `--user 1000:1000` ou user dedicado na imagem).

---

### 4.3 Limites: memória, CPUs, timeout

- **Recomendação**: **Sim** — definir limites no `docker run`:
  - `--memory=2g` (ou 4g se Ghidra em ficheiros grandes; configurável).
  - `--cpus=2` (evita consumir todos os CPUs da VM).
  - **Timeout de execução**: matar o container ao fim de N minutos (ex.: 10) via `docker run --rm` e timeout no orquestrador (ex.: `subprocess.run(..., timeout=600)` ou timeout na chamada ao Docker API). Em caso de timeout, o orquestrador devolve erro amigável à webapp.

**Resposta curta**: **Sim**: `--memory`, `--cpus` e **timeout** (ex.: 10 min) no `docker run` e no orquestrador.

---

## 5. Snapshot e limpeza da VM

### 5.1 Restaurar snapshot: reboot da VM ou só disco? Impacto no orquestrador?

- **Recomendação**: **Reboot da VM** para um snapshot limpo (ex.: diário ou após N análises) é aceitável **se** o orquestrador for reiniciado automaticamente ao arranque (systemd, Docker Compose `restart: always`, ou serviço gerido pelo cloud).
  - Alternativa: restore só de discos/ficheiros (sem reboot) — mais complexo e depende do hypervisor; para início, **reboot para snapshot** é mais simples.
  - O orquestrador deve ser tratado como “estado efémero”: ao restaurar o snapshot, a VM volta ao estado limpo; o orquestrador sobe de novo no boot. Nada de estado crítico apenas em disco na VM (ex.: fila persistente na VM sem réplica).

**Resposta curta**: **Reboot da VM** para snapshot limpo (ex.: diário); orquestrador sobe automaticamente no arranque (systemd/Docker). Nenhum serviço “sempre up” que não possa ser reiniciado com a VM.

---

### 5.2 Após a análise: apagar imediatamente ou manter X horas?

- **Recomendação**: **Apagar o ficheiro (e a pasta do job) imediatamente** após enviar o resultado à webapp.
  - Minimiza superfície de ataque e alinha com “VM limpa”. Se precisar de auditoria, os **relatórios e metadados** ficam no backend/webapp (e opcionalmente em log na VM), não os ficheiros analisados.
  - Opção alternativa: manter ficheiros por **X horas** (ex.: 24 h) numa pasta com limpeza por cron; só se houver requisito explícito de re-análise ou auditoria na VM.

**Resposta curta**: **Apagar imediatamente** após enviar o resultado; relatórios/auditoria no backend ou em logs, não os ficheiros na VM.

---

## 6. Relatórios e auditoria

### 6.1 Onde ficam os relatórios (JSON/HTML) e código C/assembly?

- **Recomendação**: **Só enviados na resposta à webapp** e **guardados no backend atual** (ou na base de dados do produto), não persistidos na VM.
  - O orquestrador lê os artefactos do container (relatório, pseudo-C, IL, `last_analysis.json`), inclui no payload da resposta (streaming NDJSON ou JSON) e o backend da webapp grava onde fizer sentido (DB, storage do utilizador, etc.).
  - Na VM não manter cópias dos relatórios após a resposta; no próximo snapshot tudo desaparece.

**Resposta curta**: Relatórios e código **só na resposta à webapp** e **guardados no backend**; **não** persistir na VM além do tempo da análise.

---

### 6.2 Registo de auditoria (quem, quê, quando, que container, resultado)

- **Recomendação**: **Sim** — registo de auditoria em **log** (e opcionalmente em base de dados no backend).
  - Na VM: log do orquestrador com job_id, timestamp, nome do ficheiro (ou hash), duração, resultado (sucesso/timeout/OOM), id do container. **Sem** conteúdo do ficheiro nem do relatório no log.
  - No backend da webapp: quem submeteu (user/session), quando, nome do ficheiro (ou hash), risk_score, e referência ao job_id para correlacionar com a VM. Dados sensíveis (conteúdo do relatório) apenas onde for necessário para o produto.

**Resposta curta**: **Sim**: auditoria em **log** (e opcionalmente BD no backend) — quem, quando, que ficheiro/job, resultado; sem expor conteúdo sensível nos logs.

---

## 7. Erros e limites

### 7.1 Container falha (crash, timeout, OOM): erro genérico ou detalhado?

- **Recomendação**: **Para o utilizador final**: mensagem **genérica e amigável** (ex.: “A análise não pôde ser concluída. Tente novamente ou com um ficheiro mais pequeno.”).
  - **Para debug/admin**: mensagens **mais detalhadas** em log (timeout, OOM, exit code do container, exceção no orquestrador), **sem** incluir conteúdo do ficheiro nem stack traces na resposta HTTP. Opcionalmente, um `error_code` (ex.: `ANALYSIS_TIMEOUT`, `ANALYSIS_OOM`) na resposta JSON para a UI mostrar uma mensagem específica (ex.: “Análise expirou; o ficheiro pode ser demasiado grande.”).

**Resposta curta**: **User-friendly**: mensagem genérica na UI. **Debug**: detalhe no log e opcionalmente `error_code` na resposta (sem dados sensíveis).

---

### 7.2 Vários uploads em paralelo: quantos concorrentes? Fila + 1 container ou várias VMs?

- **Recomendação**: Para uma **única VM**, limitar a **1 análise ativa** (ou 2–3 no máximo) para evitar sobrecarga (Ghidra e ILSpy são pesados).
  - Implementação: **fila no orquestrador** (em memória): pedidos entram na fila; um (ou N) worker(s) processa(m) um job de cada vez; os restantes esperam. A webapp pode usar polling ou manter o pedido HTTP em espera (long polling ou streaming quando o job terminar).
  - Se esperar **muitos concorrentes** (ex.: dezenas), considerar **várias VMs** com um load balancer à frente do orquestrador, ou uma fila externa (Redis/RabbitMQ) com múltiplos workers.

**Resposta curta**: **Ordem de grandeza**: assumir **poucos concorrentes** (ex.: 2–5). **Fila + 1 (ou 2) containers ativos** na VM; para mais concorrência, várias VMs ou fila distribuída.

---

## 8. Rede e acesso

### 8.1 `--network none`: análise 100% offline?

- **Recomendação**: **Sim** — os **containers de análise** devem correr com **`--network none`**.
  - Garante que ILSpy/Ghidra e qualquer script não acedem à rede (atualizações, callbacks, exfiltração). Binários maliciosos não têm conectividade.

**Resposta curta**: **Sim**: **`--network none`** nos containers de análise; análise 100% offline.

---

### 8.2 A webapp chama a VM por rede; a VM expõe só o orquestrador?

- **Recomendação**: **Sim** — a VM tem **uma interface de rede** (e uma porta, ex.: 443 ou 8443) onde **só** o serviço orquestrador está a escutar (HTTPS com TLS). O resto da VM (incluindo os containers de análise) **sem rede** ou em rede interna isolada.
  - Firewall na VM: aceitar apenas tráfego para a porta do orquestrador; bloquear saída dos containers (já garantido por `--network none`).

**Resposta curta**: **Sim**: a VM expõe **apenas uma porta** (HTTPS) para o **orquestrador**; containers de análise com **`--network none`**.

---

## Resumo das decisões

| Tópico | Decisão |
|--------|---------|
| Onde corre a webapp | Fora da VM (host/cloud); análise na VM dedicada |
| Comunicação webapp ↔ VM | API HTTP/HTTPS (upload multipart + resposta/streaming) |
| VM | Criar do zero; Linux + Docker + Docker Compose + Python orquestrador |
| Storage na VM | Disco (pasta temporária); limpeza após análise |
| Upload | Direto (multipart) da webapp para o orquestrador na VM |
| Tamanho máx. / tempo máx. | 50 MB; 10 min (configurável) |
| Criação de containers | Orquestrador na VM (1 container novo por análise) |
| ILSpy vs Ghidra | Automático por tipo de ficheiro; suportar ambos quando aplicável |
| Read-only | Ficheiro read-only; 1 volume read-write para working dir |
| User no container | Não-root (ex.: `--user 1000:1000`) |
| Limites | `--memory`, `--cpus`, timeout (ex.: 10 min) |
| Snapshot VM | Reboot para snapshot limpo; orquestrador sobe no boot |
| Ficheiros após análise | Apagar imediatamente |
| Relatórios | Só na resposta + guardados no backend; não persistir na VM |
| Auditoria | Sim (log + opcional BD), sem dados sensíveis |
| Erros ao utilizador | Mensagem genérica; detalhe e error_code em log/resposta técnica |
| Concorrência | Fila + 1–2 containers ativos; várias VMs se necessário |
| Rede containers | `--network none` |
| Rede VM | Uma porta HTTPS para o orquestrador apenas |

Este documento pode ser usado como referência para implementação e para revisão de segurança.
