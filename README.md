# RAT Analyzer

Ferramenta de Análise Automática de DLLs e Executáveis para Detecção de RATs (Remote Access Trojans)

## Descrição

Este projeto foi desenvolvido no âmbito de um projeto de licenciatura. A ferramenta combina análise estática avançada com detecção de padrões YARA para identificar possíveis Remote Access Trojans em ficheiros executáveis (.exe) e bibliotecas dinâmicas (.dll).

## Ideia final do projeto (GUI XAML + análise estática/dinâmica)

A visão final deste projeto é ter uma **aplicação principal em .NET (XAML/WPF)** que serve de ponto único de entrada para o utilizador, ligada ao backend de análise e à interface web já existente:

- **Janela principal em XAML (desktop)**  
  - O utilizador abre a aplicação desktop e vê uma janela principal construída em XAML.  
  - Pode fazer **drag and drop** de um ficheiro (ex.: `.exe`, `.dll`, `.zip` com amostra, etc.) diretamente para essa janela.
  - Assim que o ficheiro é largado, a aplicação pergunta **que tipo de análise** o utilizador pretende:
    - **Análise estática** (pipeline atual, já existente)
    - **Análise comportamental/dinâmica** (execução em VM sandbox)

- **Fluxo de Análise Estática (existente, mas integrado na GUI)**  
  - Se o utilizador escolher **Análise estática**, o backend faz:
    - Conversão/descompilação do binário para **C# / pseudo‑C** (via ILSpy, Ghidra ou ferramentas integradas).  
    - Análise estática completa (imports suspeitos, strings, YARA, técnicas de evasão, scoring, etc.).  
    - Geração de um **relatório estático detalhado**, incluindo as funções que deram flag como potencial malware/RAT.  
  - A aplicação desktop mostra um resumo e envia o resultado para a **webapp Drop & Analyze**, onde o utilizador pode consultar:
    - Código C# / pseudo‑C  
    - Relatório completo de análise estática  
    - Scores e indicadores visualizados na interface React  
    - Uma **visualização educativa do código**, recorrendo a **inteligência artificial** para:
      - Explicar, em linguagem natural, o que cada função suspeita parece fazer  
      - Destacar e comentar as chamadas de APIs nocivas ou potencialmente maliciosas  
      - Sugerir hipóteses sobre o comportamento geral da função/trojan (ex.: persistência, C2, keylogging, exfiltração), para apoiar o utilizador a **aprender análise de malware** a partir do código mostrado.

- **Fluxo de Análise Comportamental/Dinâmica (sandbox em VM)**  
  - Se o utilizador escolher **Análise comportamental**, a aplicação chama o backend para criar um **job dinâmico**.  
  - O backend, através dos drivers de VM (`hyperv`, `proxmox`, etc.), usa **PowerShell** para:
    - Criar/reativar uma **VM sandbox segura** (partindo de um snapshot limpo).  
    - Enviar o ficheiro para dentro da VM (via `vm-agent`).  
    - **Executar o ficheiro na VM** com timeout controlado.  
    - Monitorizar o **comportamento do ficheiro** (processos, filesystem, registry, rede, etc.).  
  - No fim, o backend recolhe o **relatório comportamental** da VM e:
    - Devolve um resumo à aplicação desktop (estado, indicadores principais).  
    - Envia o relatório completo para o **site web** (Drop & Analyze) para visualização detalhada, lado a lado com a análise estática (quando existir).

Com isto, o utilizador passa a ter um **fluxo integrado**:
1. Arrasta o ficheiro para a **janela XAML**.  
2. Escolhe **Estática**, **Dinâmica** ou **Ambas**.  
3. A aplicação coordena o backend, a sandbox de VMs e a webapp para apresentar:
   - Código descompilado (C#/pseudo‑C)  
   - Relatório de análise estática  
   - Relatório de análise comportamental em VM  
   num único ecossistema de ferramentas.

## Funcionalidades

- **Análise Estática**: Identifica imports suspeitos, strings de Command & Control, técnicas de evasão e padrões de malware conhecido
- **Scanner YARA**: Detecta padrões de RATs conhecidos usando regras YARA customizáveis
- **Deobfuscação**: Aplica técnicas básicas de deobfuscação para revelar código ofuscado
- **Scoring de Risco**: Calcula um score de risco de 0-100 baseado em múltiplos fatores
- **Relatórios Detalhados**: Gera relatórios completos em formato texto

## Requisitos

- Python 3.10+
- Bibliotecas Python (ver `backend/requirements.txt`)

## Instalação

1. Clone ou baixe este repositório

2. Instale as dependências:
```bash
pip install -r backend/requirements.txt
```

3. **Nota sobre YARA**: Para usar o scanner YARA, é necessário instalar a biblioteca YARA no sistema:
   - **Windows**: Baixe de https://github.com/VirusTotal/yara/releases
   - **Linux**: `sudo apt-get install yara` ou `sudo yum install yara`
   - **macOS**: `brew install yara`

4. **Opcional — Decompilação para pseudo-C (binários nativos)**: Para converter assembly em código C legível (Ghidra):
   - Instale [Ghidra 12+](https://github.com/NationalSecurityAgency/ghidra/releases) e descompacte numa pasta (ex.: `C:\ghidra_12.0_PUBLIC`).
   - Defina a variável de ambiente `GHIDRA_INSTALL_DIR` com o caminho dessa pasta.
   - O pacote `pyghidra` (em `requirements.txt`) permite usar o decompilador Ghidra a partir do Python. Sem Ghidra instalado, a análise continua a funcionar; apenas não será gerado o ficheiro pseudo-C para binários nativos.

## Uso

### Interface web (recomendado)
A aplicação **Drop & Analyze** é uma interface web em React que se liga a este backend. Permite arrastar ficheiros .exe ou .dll e ver relatórios, pseudo-C e IL em tempo real.

1. Inicie o backend (servidor Python que expõe a API).
2. Na pasta `frontend`, execute `npm i` e `npm run dev`.
3. Abra o URL indicado (ex.: http://localhost:8080) e arraste ficheiros para analisar.

Consulte `frontend/README.md` para mais detalhes.

### Interface gráfica Python (recomendado para projetos .NET)
Arraste um ficheiro `.cs` (ou selecione-o), compile o projeto e escolha analisar o `.exe` ou o `.dll`:

```bash
pip install -r requirements.txt   # inclui windnd para drag-and-drop no Windows
python rat_analyzer_gui.py
```

1. Arraste um ficheiro **.cs** para a janela (ou use "Procurar ficheiro .cs")
2. Clique em **Compilar (dotnet publish)** para gerar o .exe e .dll
3. Escolha **Analisar o .exe** ou **Analisar o .dll**
4. Clique em **Executar análise RAT**. Os relatórios são guardados em `reports/`

### Análise básica (linha de comandos):
```bash
python rat_analyzer.py caminho/para/ficheiro.exe
```

### Com opções:
```bash
python rat_analyzer.py caminho/para/ficheiro.dll -o relatorios/ -v
```

### Modo servidor com fila (opcional)

Na pasta `backend/`:

```bash
pip install -r requirements.txt

# Backend FastAPI
uvicorn api:app --reload --port 8000

# (Opcional) Redis + worker RQ para processar jobs fora do processo da API
set REDIS_URL=redis://localhost:6379/0         # Windows (PowerShell/CMD)
python worker.py
```

Se `REDIS_URL` **não** estiver definido, o backend continua a funcionar: os jobs de análise correm em threads locais (modo desenvolvimento).

### Parâmetros:
- `file`: Caminho para o ficheiro .exe ou .dll a analisar (obrigatório)
- `-o, --output`: Directório de saída para relatórios (padrão: `reports`)
- `-v, --verbose`: Modo verboso com informações detalhadas

### Limpar caches e ficheiros temporários
Remove apenas caches e artefactos gerados (não apaga código fonte nem relatórios):

```bash
python clean.py
```

Apaga: `__pycache__/`, `.pytest_cache`, `*.pyc`/`*.pyo`, `programa/bin/`, `programa/obj/`, `decompiled/`. Para simular sem apagar, use `python clean.py --dry-run`.

## Estrutura do Projeto

```
PROJETO/
├── backend/                 # API FastAPI + pipeline de análise
│   ├── api.py               # Endpoints /api/analyze, /api/analyze_stream, /api/analysis
│   ├── analysis_jobs.py     # Jobs static|dynamic|both
│   ├── config.py            # Configuração central (paths, DB, sandbox_jobs)
│   ├── modules/             # Módulos (static analyzer, yara, deobfuscator, decompilers, etc.)
│   └── vm_drivers/          # Drivers dinâmicos (stub, hyperv, proxmox)
├── frontend/                # Interface web (React/Vite) – ver frontend/README.md
├── wpf-gui/                 # App desktop WPF (.NET 8)
├── vm-agent/                # Agent HTTP para correr dentro da VM sandbox
├── scripts/hyperv-sandbox/  # Scripts PowerShell de automação Hyper-V
├── sandbox_jobs/            # Jobs e artefactos (SQLite + outputs por job)
└── README.md
```

Os paths de `sandbox_jobs/`, base de dados e diretórios de saída são definidos em `backend/config.py`.

## Diagramas PUML

Os diagramas atualizados estão em `docs/diagrams/`:

- `analysis-sequence-overview.puml` (visão integrada)
- `analysis-activity-static.puml` (atividade da análise estática)
- `analysis-activity-dynamic.puml` (atividade da análise dinâmica em VM)

## Módulos

### Static Analyzer
Analisa ficheiros PE sem executá-los:
- Identifica imports suspeitos (networking, criptografia, sistema)
- Detecta funções suspeitas (CreateRemoteThread, socket, etc.)
- Extrai strings de C&C (URLs, IPs, tokens)
- Identifica técnicas de evasão (anti-debug, anti-VM)
- Calcula entropia das secções (detecção de packing)
- Detecta indicadores de packers conhecidos

### YARA Scanner
- Compila e executa regras YARA
- Detecta padrões genéricos de RATs
- Identifica padrões de comunicação C&C
- Detecta técnicas de evasão

### Deobfuscator
- Detecta strings XOR
- Decodifica strings Base64
- Identifica indicadores de ofuscação

### Risk Scorer
Calcula score de risco baseado em:
- Imports suspeitos (15 pontos)
- Funções suspeitas (20 pontos)
- Strings C&C (25 pontos)
- Técnicas de evasão (15 pontos)
- Matches YARA (20 pontos)
- Indicadores de packer (10 pontos)
- Ofuscação (10 pontos)
- Entropia alta (5 pontos)

**Níveis de Risco:**
- 80-100: CRÍTICO
- 60-79: ALTO
- 40-59: MÉDIO
- 20-39: BAIXO
- 0-19: MUITO BAIXO

## Integração com Ferramentas Externas

### Conversão de EXE/DLL para Source Code
O projeto está preparado para integrar ferramentas que convertem executáveis para código fonte. Algumas opções:

- **Ghidra** (gratuito): Descompilador avançado
- **IDA Pro** (comercial): Descompilador profissional
- **Radare2** (gratuito): Framework de análise reversa
- **RetDec** (gratuito): Descompilador online/offline

Para integrar, modifique o módulo `static_analyzer.py` ou crie um novo módulo que processe o código fonte gerado.

### Deobfuscadores Avançados
Para deobfuscação mais avançada, pode integrar:
- **de4dot** (para .NET)
- Scripts customizados para Ghidra/IDA
- Ferramentas específicas de deobfuscação

## Personalização

### Adicionar Regras YARA
Coloque ficheiros `.yar` no directório `yara_rules/`. O scanner compilará automaticamente todas as regras.

### Ajustar Pesos do Score
Edite `backend/modules/risk_scorer.py` para ajustar os pesos dos diferentes fatores.

### Adicionar Padrões de Detecção
- **Imports suspeitos**: Edite `SUSPICIOUS_IMPORTS` em `backend/modules/static_analyzer.py`
- **Funções suspeitas**: Edite `SUSPICIOUS_FUNCTIONS` em `backend/modules/static_analyzer.py`
- **Padrões C&C**: Edite `C2_PATTERNS` em `backend/modules/static_analyzer.py`

## Limitações

- Análise dinâmica depende de infraestrutura de sandbox (VM + vm-agent + configuração de variáveis)
- O driver `stub` (default) não executa o ficheiro; serve apenas para validar o fluxo end-to-end
- Deobfuscação básica (pode não funcionar com ofuscação avançada)
- Requer instalação de YARA no sistema
- Regras YARA básicas incluídas (recomenda-se adicionar mais)

## Melhorias Futuras

- [ ] Integração com IDA (descompilação; Ghidra já integrado)
- [ ] Deobfuscação avançada
- [ ] Telemetria dinâmica avançada no vm-agent (Sysmon/ETW/hooking) e enriquecimento automático de `dynamicReport`
- [ ] Suporte para mais formatos de ficheiro
- [ ] Base de dados de assinaturas de malware conhecido
- [ ] Análise de rede (tráfego C&C)

## Licença

Este projeto foi desenvolvido no âmbito académico.

## Autor

Desenvolvido como projeto de licenciatura.

## Contribuições

Sugestões e melhorias são bem-vindas!

---

## Sandbox de VMs (Análise Dinâmica) — Pipeline nova

Este repositório agora inclui uma base para **análise dinâmica** (execução em sandbox), integrada com o frontend.

### Endpoints principais

- **Estática (streaming)**: `POST /api/analyze_stream`  
  Mantém o comportamento existente (NDJSON com logs + resultado).

- **Pipeline de jobs (estática/dinâmica/ambas)**:
  - `POST /api/analysis?analysis_type=static|dynamic|both`
  - `GET /api/analysis/{job_id}`

Os jobs são guardados em `sandbox_jobs/{job_id}/` (ver `backend/config.py` → `SANDBOX_JOBS_DIR`).

### Driver de sandbox dinâmica (plugável)

O orquestrador dinâmico (`backend/vm_orchestrator.py`) escolhe um driver via variável de ambiente:

- `SANDBOX_VM_DRIVER=stub` (**default**, seguro)  
  Não executa o ficheiro. Apenas devolve um relatório sintético para validar o fluxo end-to-end.

- `SANDBOX_VM_DRIVER=proxmox` (skeleton)  
  Preparado para ligar a um Proxmox/VM real, mas ainda não implementado.

### Variáveis de ambiente (para ligar um hypervisor real)

Estas variáveis não têm valores fixos; configure-as no seu ambiente quando for integrar uma sandbox real:

- `SANDBOX_VM_DRIVER`: `stub` | `proxmox` | `hyperv`

Para **Proxmox**:
- `PROXMOX_API_URL`
- `PROXMOX_TOKEN_ID`
- `PROXMOX_TOKEN_SECRET`
- `PROXMOX_NODE`
- `PROXMOX_VMID`
- `PROXMOX_SNAPSHOT`

Para **Hyper-V (Windows host local)**:
- `HYPERV_VM_NAME` — nome exato da VM no Hyper-V (ex.: `win-sandbox`)
- `HYPERV_SNAPSHOT_NAME` — nome do checkpoint “limpo” (ex.: `clean-snap`)

Comum aos dois:
- `VM_AGENT_BASE_URL` — URL HTTP do VM Agent (ex.: `http://192.168.100.10:5000`)

Timeouts (opcionais, aplicam-se aos dois drivers):
- `SANDBOX_HTTP_TIMEOUT_SECONDS`
- `SANDBOX_BOOT_WAIT_SECONDS`
- `SANDBOX_AGENT_WAIT_SECONDS`
- `SANDBOX_DYNAMIC_TIMEOUT_SECONDS`

### Protocolo esperado do VM Agent (futuro)

Quando a sandbox real estiver ligada, recomenda-se um **agent dentro da VM** (Windows guest) com uma API HTTP interna (apenas rede isolada) com operações como:

- `POST /api/upload` → recebe a amostra
- `POST /api/run` → executa com timeout e inicia monitorização (Sysmon/ETW/Procmon)
- `GET /api/report` → devolve JSON comportamental (processos, filesystem, registry, rede, mutex, persistência, etc.)

O backend deve:
- Reverter snapshot limpo antes/depois de cada job.
- Garantir que nenhum artefacto é persistido fora da sandbox.

### VM Agent incluído neste repositório

Na pasta `vm-agent/` existe um **agent de exemplo em .NET 8** (minimal API) pronto a correr dentro da VM Windows:

- Endpoints:
  - `GET /api/health` — healthcheck simples
  - `POST /api/upload` — recebe o ficheiro (campo `file`) e grava em `samples/`
  - `POST /api/run` — executa a amostra com timeout configurável (`{"timeoutSeconds": 300}`) e guarda stdout/stderr/exitCode
  - `GET /api/report` — devolve JSON com:
    - `status`, `startedAt`, `finishedAt`, `exitCode`, `stdout`, `stderr`
    - placeholders vazios para `processes`, `fileSystem`, `registry`, `network`, `mutexes`, `persistence`, `privilegeEscalation`, `sensitiveApiCalls`

Passos básicos dentro da VM:

```bash
cd C:\caminho\para\PROJETO\vm-agent
dotnet build -c Release
dotnet run --urls http://0.0.0.0:5000
```

E configure no host:

- `VM_AGENT_BASE_URL=http://IP_DA_VM:5000`
- `SANDBOX_VM_DRIVER=hyperv` (ou `proxmox` se usar Proxmox)

Quando adicionar Sysmon/ETW/hooking, basta preencher as listas no JSON de `/api/report` — o backend já está preparado para guardar esse objeto em `dynamicReport` e enviá-lo para o frontend.

---

## Guia completo: criar a VM de sandbox no Hyper-V (Windows)

Este guia descreve **todos os passos**, sem resumos, para ter uma VM Windows isolada (sem internet) no Hyper-V, pronta para análise dinâmica com o driver `hyperv`.

**Alternativa com relatório via porta serial (sem HTTP):** na pasta **`scripts/hyperv-sandbox/`** existe um fluxo completo que usa **D:\PROJETOVM**, cria a VM, executa a amostra na VM, monitoriza alterações (ficheiros, registry, processos, rede, serviços, tarefas agendadas) e envia o relatório em .txt para o host através de uma **porta serial virtual** (Named Pipe), sem rede nem VM Agent. Ver `scripts/hyperv-sandbox/README.md`.

### Pré-requisitos

- Windows 10 Pro/Enterprise ou Windows 11 Pro/Enterprise (ou Windows Server) com Hyper-V disponível.
- Permissões de administrador no PC.
- Espaço em disco livre (recomendado: pelo menos 80 GB para a VM + espaço para o ISO do Windows).
- Ficheiro ISO da instalação do Windows (10 ou 11).

---

### 1. Ativar o Hyper-V

Abre **PowerShell como Administrador** e executa:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

- `-Online` — aplica à instalação Windows atual.
- `-FeatureName Microsoft-Hyper-V` — ativa o papel Hyper-V.
- `-All` — inclui subfuncionalidades (Hyper-V Platform, Hyper-V Management Tools, etc.).

Reinicia o computador quando for pedido.

Para confirmar que está ativo:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
```

O campo `State` deve estar `Enabled`.

---

### 2. Criar o switch virtual (rede isolada, sem internet)

A VM de sandbox deve usar uma rede **Internal**: comunica apenas com o host (e outras VMs no mesmo switch), **sem acesso à internet**. Assim consegues ver tentativas de rede do malware sem risco de fuga.

Em **PowerShell como Administrador**:

```powershell
New-VMSwitch -Name "SandboxSwitch" -SwitchType Internal
```

- `-Name "SandboxSwitch"` — nome do switch (podes usar outro; terás de o referir ao criar a VM).
- `-SwitchType Internal` — rede interna: VM e host partilham um segmento lógico; não há bridge para o adaptador físico nem NAT por defeito.

Opcional: atribuir um endereço ao adaptador virtual do host neste switch, para a VM conseguir falar com o host (e o backend) por IP fixo. Por exemplo, rede `192.168.100.0/24`:

```powershell
Get-NetAdapter | Where-Object { $_.Name -like "*SandboxSwitch*" } | ForEach-Object {
    New-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress 192.168.100.1 -PrefixLength 24
}
```

Assim, dentro da VM podes configurar, por exemplo, `192.168.100.10` com gateway `192.168.100.1`; o backend no host usará `VM_AGENT_BASE_URL=http://192.168.100.10:5000`.

---

### 3. Criar a pasta para os ficheiros da VM

Escolhe um disco com espaço (ex.: `D:`). Cria pastas para o disco virtual e, se quiseres, para ISOs:

```powershell
New-Item -ItemType Directory -Path "D:\VMs" -Force
New-Item -ItemType Directory -Path "D:\VMs\win-sandbox" -Force
New-Item -ItemType Directory -Path "D:\ISOs" -Force
```

Coloca o ISO do Windows em `D:\ISOs\`, por exemplo `Win10_22H2.iso`. Ajusta o caminho nos comandos abaixo se usares outro nome ou localização.

---

### 4. Criar a VM (Gen 2, UEFI)

Cria a VM em modo **Gen 2** (UEFI; necessário para Windows 10/11 moderno):

```powershell
$VMName = "win-sandbox"
$VMPath = "D:\VMs\win-sandbox"
$SwitchName = "SandboxSwitch"

New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes 4GB `
    -SwitchName $SwitchName `
    -Path $VMPath `
    -NewVHDPath "$VMPath\win-sandbox.vhdx" `
    -NewVHDSizeBytes 80GB
```

Parâmetros:

- `-Name` — nome da VM (será o `HYPERV_VM_NAME`).
- `-Generation 2` — VM UEFI (Secure Boot, etc.).
- `-MemoryStartupBytes 4GB` — RAM inicial (podes aumentar para 8GB se tiveres).
- `-SwitchName` — switch criado no passo 2 (rede isolada).
- `-Path` — pasta de configuração da VM.
- `-NewVHDPath` — caminho do disco virtual (será criado automaticamente).
- `-NewVHDSizeBytes 80GB` — tamanho do disco (ajusta se precisares).

---

### 5. Ajustar processadores e firmware (opcional)

Para dar 4 vCPUs e garantir que arranca a partir do DVD na primeira vez:

```powershell
Set-VMProcessor -VMName $VMName -Count 4
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes 4GB
```

Desligar Secure Boot pode ser necessário se o ISO não tiver assinaturas reconhecidas; só se a instalação falhar no arranque:

```powershell
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
```

---

### 6. Ligar o DVD à VM e definir ordem de arranque

Assumindo que o ISO está em `D:\ISOs\Win10_22H2.iso`:

```powershell
Add-VMDvdDrive -VMName $VMName -Path "D:\ISOs\Windows.iso"
$dvd = Get-VMDvdDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd
```

- `Add-VMDvdDrive` — associa o ISO como drive de DVD.
- `Set-VMFirmware -FirstBootDevice $dvd` — a VM arranca primeiro pelo DVD (para instalar o Windows).

---

### 7. Arrancar a VM e instalar o Windows

```powershell
Start-VM -Name $VMName
```

Abre o **Hyper-V Manager** (opcional): `virtmgmt.msc`, liga-te à VM e abre "Connect" para ver o ecrã da VM.

- Arranca a partir do DVD e completa a instalação do Windows (idioma, partição única, conta local ou sem conta, etc.).
- Quando o Windows estiver no ambiente de trabalho, **desliga a VM** antes de criar o checkpoint (opcional mas recomendado para snapshot limpo):

```powershell
Stop-VM -Name $VMName -Force
```

---

### 8. Configurar a rede dentro da VM (IP estático)

Liga de novo a VM e entra na consola:

```powershell
Start-VM -Name $VMName
```

Dentro da VM (Windows):

1. Abre **Definições → Rede e Internet → Ethernet** (ou o adaptador ligado ao switch interno).
2. **Editar** em "Atribuição de endereço IP" → **Manual**.
3. Ativa **IPv4** e define, por exemplo:
   - Endereço IP: `192.168.100.10`
   - Máscara: `255.255.255.0`
   - Gateway: `192.168.100.1` (IP do host no switch; pode ficar vazio se não quiseres gateway).
   - DNS: deixa vazio ou `127.0.0.1` — não queres que a VM resolva domínios na internet.

Guarda. A VM fica com IP fixo na rede interna; **sem gateway/DNS útil, não há internet**.

---

### 9. Instalar o VM Agent dentro da VM

Dentro da VM:

1. Copia para a VM a pasta **`vm-agent`** do teu projeto (pen USB, partilha de pasta do Hyper-V, ou outro método).
   - Por exemplo, coloca em `C:\vm-agent\`.
2. Abre **PowerShell** ou **Cmd** como utilizador normal (não é preciso admin para correr o agent).
3. Instala .NET 8 SDK se ainda não tiver (download em https://dotnet.microsoft.com/download/dotnet/8.0 — podes transferir o instalador no host e passar para a VM).
4. Na pasta do agent:

```powershell
cd C:\vm-agent
dotnet restore
dotnet build -c Release
dotnet run --urls http://0.0.0.0:5000
```

O agent fica a escutar em todas as interfaces na porta 5000. No host, o backend usará `VM_AGENT_BASE_URL=http://192.168.100.10:5000` (ou o IP que definiste).

Para testar a partir do host (PowerShell):

```powershell
Invoke-RestMethod -Uri "http://192.168.100.10:5000/api/health" -UseBasicParsing
```

Deve devolver algo como `{ "status": "ok", "component": "vm-agent" }`.

---

### 10. Desligar a VM e criar o checkpoint "limpo"

Quando a VM estiver pronta (Windows instalado, rede estática configurada, vm-agent instalado e testado), desliga-a e cria um checkpoint. Este será o estado para onde o driver `hyperv` reverterá antes de cada análise:

```powershell
Stop-VM -Name $VMName -Force
Checkpoint-VM -VMName $VMName -SnapshotName "clean-snap" -Description "Estado limpo para sandbox; Windows + vm-agent configurados; rede isolada."
```

Listar checkpoints para confirmar:

```powershell
Get-VMSnapshot -VMName $VMName
```

O nome `clean-snap` é o que deves usar em `HYPERV_SNAPSHOT_NAME`.

---

### 11. Configurar o backend no host

No **PowerShell** (ou CMD) onde vais executar o backend, define as variáveis de ambiente e arranca a API:

```powershell
$env:SANDBOX_VM_DRIVER = "hyperv"
$env:HYPERV_VM_NAME = "win-sandbox"
$env:HYPERV_SNAPSHOT_NAME = "clean-snap"
$env:VM_AGENT_BASE_URL = "http://192.168.100.10:5000"

cd C:\Users\jmigu\Desktop\PROJETO\PROJETO\backend
uvicorn api:app --reload --host 0.0.0.0 --port 8000
```

Ajusta `VM_AGENT_BASE_URL` se usaste outro IP na VM.

---

### 12. Uso na webapp (drag-and-drop)

1. Arranca o frontend (`npm run dev` em `frontend`).
2. Escolhe **"Apenas dinâmica"** ou **"Ambas"**.
3. Faz upload do ficheiro (drag-and-drop ou seleção).

O backend irá:

1. Restaurar o checkpoint `clean-snap` (`Restore-VMSnapshot`).
2. Arrancar a VM (`Start-VM`).
3. Esperar o agent em `/api/health`.
4. Enviar o ficheiro para `/api/upload`.
5. Chamar `/api/run` (execução na VM com timeout).
6. Recolher o relatório em `/api/report` e devolvê-lo à webapp.

A VM fica em rede isolada; tentativas de DNS/TCP/HTTP do malware podem ser registadas pelo agent (e no futuro por Sysmon/ETW) sem que o tráfego saia para a internet.

---

### Resumo dos comandos PowerShell (referência rápida)

| Objetivo | Comando |
|----------|--------|
| Ativar Hyper-V | `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All` |
| Criar switch interno | `New-VMSwitch -Name "SandboxSwitch" -SwitchType Internal` |
| Criar VM Gen2 + disco 80GB | `New-VM -Name "win-sandbox" -Generation 2 -MemoryStartupBytes 4GB -SwitchName "SandboxSwitch" -Path "D:\VMs\win-sandbox" -NewVHDPath "D:\VMs\win-sandbox\win-sandbox.vhdx" -NewVHDSizeBytes 80GB` |
| 4 vCPUs | `Set-VMProcessor -VMName "win-sandbox" -Count 4` |
| Ligar ISO | `Add-VMDvdDrive -VMName "win-sandbox" -Path "D:\ISOs\Win10_22H2.iso"; Set-VMFirmware -VMName "win-sandbox" -FirstBootDevice (Get-VMDvdDrive -VMName "win-sandbox")` |
| Arrancar / Parar | `Start-VM -Name "win-sandbox"` / `Stop-VM -Name "win-sandbox" -Force` |
| Checkpoint limpo | `Checkpoint-VM -VMName "win-sandbox" -SnapshotName "clean-snap"` |
| Restaurar checkpoint (ex.: pelo driver) | `Restore-VMSnapshot -VMName "win-sandbox" -Name "clean-snap" -Confirm:$false` |

