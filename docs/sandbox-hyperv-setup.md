# Análise dinâmica: sandbox em VM (Hyper-V e Proxmox)

Este documento descreve, em detalhe, a **análise dinâmica** (execução de amostras numa sandbox isolada)
e como preparar uma VM Windows no Hyper-V de raiz. É o guia de referência completo; para uma visão geral
do projeto consulte o [README principal](../README.md).

> **Alternativa por porta serial (sem HTTP/VM Agent):** a pasta
> [`scripts/hyperv-sandbox/`](../scripts/hyperv-sandbox/README.md) contém um fluxo completo que cria a VM,
> executa a amostra, monitoriza alterações (ficheiros, registry, processos, rede, serviços, tarefas
> agendadas) e devolve o relatório ao host por **Named Pipe (COM1)** e/ou **Copy-VMFile**, sem rede.

---

## Endpoints principais

- **Estática (streaming)**: `POST /api/analyze_stream`
  Mantém o comportamento existente (NDJSON com logs + resultado).

- **Pipeline de jobs (estática/dinâmica/ambas)**:
  - `POST /api/analysis?analysis_type=static|dynamic|both`
  - `POST /api/analysis/upload_static` — publicar resultado estático já calculado noutro processo no mesmo `job_id`
  - `GET /api/analysis/{job_id}` — estado e artefactos do job
  - `GET /api/analysis/{job_id}/artifacts/obfuscated_snippets` — excertos ofuscados (texto)
  - `GET /api/analyses` — listagem de jobs recentes

Os jobs são guardados em `sandbox_jobs/{job_id}/` (ver `backend/config.py` → `SANDBOX_JOBS_DIR`).

## Driver de sandbox dinâmica (plugável)

O orquestrador dinâmico (`backend/vm_orchestrator.py`) escolhe um driver via variável de ambiente:

- `SANDBOX_VM_DRIVER=stub` (**default**, seguro)
  Não executa o ficheiro. Apenas devolve um relatório sintético para validar o fluxo end-to-end.

- `SANDBOX_VM_DRIVER=hyperv`
  Usa uma VM Hyper-V local (ver guia abaixo) ou o fluxo serial em `scripts/hyperv-sandbox/`.

- `SANDBOX_VM_DRIVER=proxmox` (skeleton)
  Preparado para ligar a um Proxmox/VM real, mas ainda não implementado.

## Variáveis de ambiente (para ligar um hypervisor real)

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
- `HYPERV_SNAPSHOT_NAME` — nome do checkpoint "limpo" (ex.: `clean-snap`)

Comum aos dois:
- `VM_AGENT_BASE_URL` — URL HTTP do VM Agent (ex.: `http://192.168.100.10:5000`)

Timeouts (opcionais, aplicam-se aos dois drivers):
- `SANDBOX_HTTP_TIMEOUT_SECONDS`
- `SANDBOX_BOOT_WAIT_SECONDS`
- `SANDBOX_AGENT_WAIT_SECONDS`
- `SANDBOX_DYNAMIC_TIMEOUT_SECONDS`

## Protocolo esperado do VM Agent

Quando a sandbox real estiver ligada, recomenda-se um **agent dentro da VM** (Windows guest) com uma API
HTTP interna (apenas rede isolada) com operações como:

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

Quando adicionar Sysmon/ETW/hooking, basta preencher as listas no JSON de `/api/report` — o backend já está
preparado para guardar esse objeto em `dynamicReport` e enviá-lo para o frontend.

---

## Guia completo: criar a VM de sandbox no Hyper-V (Windows)

Este guia descreve **todos os passos**, sem resumos, para ter uma VM Windows isolada (sem internet) no
Hyper-V, pronta para análise dinâmica com o driver `hyperv`.

### Pré-requisitos

- Windows 10 Pro/Enterprise ou Windows 11 Pro/Enterprise (ou Windows Server) com Hyper-V disponível.
- Permissões de administrador no PC.
- Espaço em disco livre (recomendado: pelo menos 80 GB para a VM + espaço para o ISO do Windows).
- Ficheiro ISO do Windows (10 ou 11). **Sandbox Hyper-V unattended:** ISO **en-US** (English United States) apenas — ver [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) e `_Config.ps1`.

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

A VM de sandbox deve usar uma rede **Internal**: comunica apenas com o host (e outras VMs no mesmo switch),
**sem acesso à internet**. Assim consegues ver tentativas de rede do malware sem risco de fuga.

Em **PowerShell como Administrador**:

```powershell
New-VMSwitch -Name "SandboxSwitch" -SwitchType Internal
```

- `-Name "SandboxSwitch"` — nome do switch (podes usar outro; terás de o referir ao criar a VM).
- `-SwitchType Internal` — rede interna: VM e host partilham um segmento lógico; não há bridge para o adaptador físico nem NAT por defeito.

Opcional: atribuir um endereço ao adaptador virtual do host neste switch, para a VM conseguir falar com o
host (e o backend) por IP fixo. Por exemplo, rede `192.168.100.0/24`:

```powershell
Get-NetAdapter | Where-Object { $_.Name -like "*SandboxSwitch*" } | ForEach-Object {
    New-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress 192.168.100.1 -PrefixLength 24
}
```

Assim, dentro da VM podes configurar, por exemplo, `192.168.100.10` com gateway `192.168.100.1`; o backend
no host usará `VM_AGENT_BASE_URL=http://192.168.100.10:5000`.

---

### 3. Criar a pasta para os ficheiros da VM

Escolhe um disco com espaço (ex.: `D:`). Cria pastas para o disco virtual e, se quiseres, para ISOs:

```powershell
New-Item -ItemType Directory -Path "D:\VMs" -Force
New-Item -ItemType Directory -Path "D:\VMs\win-sandbox" -Force
New-Item -ItemType Directory -Path "D:\ISOs" -Force
```

Coloca o ISO do Windows em `D:\ISOs\`, por exemplo `Win10_22H2.iso`. Ajusta o caminho nos comandos abaixo
se usares outro nome ou localização.

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

Desligar Secure Boot pode ser necessário se o ISO não tiver assinaturas reconhecidas; só se a instalação
falhar no arranque:

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

O agent fica a escutar em todas as interfaces na porta 5000. No host, o backend usará
`VM_AGENT_BASE_URL=http://192.168.100.10:5000` (ou o IP que definiste).

Para testar a partir do host (PowerShell):

```powershell
Invoke-RestMethod -Uri "http://192.168.100.10:5000/api/health" -UseBasicParsing
```

Deve devolver algo como `{ "status": "ok", "component": "vm-agent" }`.

---

### 10. Desligar a VM e criar o checkpoint "limpo"

Quando a VM estiver pronta (Windows instalado, rede estática configurada, vm-agent instalado e testado),
desliga-a e cria um checkpoint. Este será o estado para onde o driver `hyperv` reverterá antes de cada análise:

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

cd backend   # a partir da raiz do repositório clonado
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

A VM fica em rede isolada; tentativas de DNS/TCP/HTTP do malware podem ser registadas pelo agent (e no
futuro por Sysmon/ETW) sem que o tráfego saia para a internet.

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
