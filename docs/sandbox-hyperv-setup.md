# Análise dinâmica: sandbox em VM (Hyper-V e Proxmox)

Este documento descreve, em detalhe, a **análise dinâmica** (execução de amostras numa sandbox isolada)
e como preparar uma VM Windows no Hyper-V de raiz. É o guia de referência completo; para uma visão geral
do projeto consulte o [README principal](../README.md).

> **Aviso Gen1 vs Gen2:** Este guia descreve o **Caminho A** (backend + VM Agent HTTP). A VM pode ser **Gen2**
> (exemplo manual `win-sandbox` abaixo). O **Caminho B** (WPF / `04-Run-Sample.ps1`) funciona com **Gen1 ou Gen2**
> (cópia via PsDirect) - ver [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md).

> **Alternativa PowerShell (sem HTTP/VM Agent):** a pasta
> [`scripts/hyperv-sandbox/`](../scripts/hyperv-sandbox/README.md) contém um fluxo **independente** (Caminho B)
> usado pela app WPF: executa a amostra na VM, monitoriza alterações e copia o relatório para o host via
> **PsDirect / Copy-VMFile**, com verificação **SHA256** após a cópia. **Não** é invocado pelo driver `hyperv.py` do backend.

## Índice

- [Resumo rápido (Caminho A)](#resumo-rápido-caminho-a)
- [Endpoints principais](#endpoints-principais)
- [Driver de sandbox dinâmica (plugável)](#driver-de-sandbox-dinâmica-plugável)
- [Variáveis de ambiente](#variáveis-de-ambiente-para-ligar-um-hypervisor-real)
- [VM Agent HTTP (implementado)](#vm-agent-http-implementado)
- [Guia manual Hyper-V (Caminho A)](#guia-manual-hyper-v-caminho-a--vm-agent)

---

## Resumo rápido (Caminho A)

1. Ativar Hyper-V e criar switch **Internal** (sem internet).
2. Criar VM Windows (**Gen2** neste guia manual, ou partilhar nomes com `_Config.ps1`).
3. IP estático na VM (ex.: `192.168.100.10`); instalar **vm-agent** com `VM_AGENT_TOKEN`.
4. Criar checkpoint limpo (`clean-snap` ou `CleanState`).
5. No host: `SANDBOX_VM_DRIVER=hyperv`, `VM_AGENT_BASE_URL`, `VM_AGENT_TOKEN`.
6. Frontend/backend: análise **dinâmica** ou **ambas**.

Detalhe nas seções seguintes. Telemetria completa: **Caminho B** - [`docs/README.md`](../docs/README.md#análise-dinâmica--qual-caminho-usar).

---

### Mapeamento de configuração (Caminho A)

| Variável de ambiente (backend) | Equivalente em `_Config.ps1` (Caminho B) | Notas |
|--------------------------------|----------------------------------------|-------|
| `HYPERV_VM_NAME` | `PROJETOVM_VMName` (`MalwareSandbox`) | Nome exato da VM no Hyper-V |
| `HYPERV_SNAPSHOT_NAME` | `PROJETOVM_SnapshotName` (`CleanState`) | Checkpoint limpo |
| `VM_AGENT_BASE_URL` | - | Ex.: `http://192.168.100.10:5000` (IP estático na VM) |
| `VM_AGENT_TOKEN` | - | Header `X-Agent-Token` (**obrigatório** no arranque do agent; dev: `VM_AGENT_ALLOW_INSECURE=1`) |
| `SANDBOX_VM_OP_TIMEOUT_SECONDS` | - | Timeout PowerShell restore/start (default 120 s) |

---

## Endpoints principais

- **Estática (streaming)**: `POST /api/analyze_stream`
  Mantém o comportamento existente (NDJSON com logs + resultado).

- **Pipeline de jobs (estática/dinâmica/ambas)**:
  - `POST /api/analysis?analysis_type=static|dynamic|both`
  - `POST /api/analysis/upload_static` - publicar resultado estático já calculado noutro processo no mesmo `job_id`
  - `GET /api/analysis/{job_id}` - estado e artefatos do job
  - `GET /api/analysis/{job_id}/artifacts/obfuscated_snippets` - excertos ofuscados (texto)
  - `GET /api/analyses` - listagem de jobs recentes

Os jobs são guardados em `sandbox_jobs/{job_id}/` (ver `backend/config.py` → `SANDBOX_JOBS_DIR`).

## Driver de sandbox dinâmica (plugável)

O orquestrador dinâmico (`backend/vm_orchestrator.py`) escolhe um driver via variável de ambiente:

- `SANDBOX_VM_DRIVER=stub` (**default**, seguro)
  Não executa o ficheiro. Apenas devolve um relatório sintético para validar o fluxo end-to-end.

- `SANDBOX_VM_DRIVER=hyperv`
  Restaura snapshot e arranca a VM via PowerShell; comunica com o **VM Agent HTTP**
  ([`vm-agent/README.md`](../vm-agent/README.md)).
  **Não** executa `04-Run-Sample.ps1` - esse script pertence ao Caminho B (WPF).

- `SANDBOX_VM_DRIVER=proxmox`
  Driver Proxmox via API REST + VM Agent HTTP. **Experimental** - código em `backend/vm_drivers/proxmox.py`,
  sem guia passo-a-passo nem testes de integração no CI. Requer todas as variáveis `PROXMOX_*` abaixo.

## Variáveis de ambiente (para ligar um hypervisor real)

Estas variáveis não têm valores fixos; configure-as no seu ambiente quando for integrar uma sandbox real:

- `SANDBOX_VM_DRIVER`: `stub` | `proxmox` | `hyperv`

Para **Proxmox** *(experimental - não validado no CI)*:
- `PROXMOX_API_URL`
- `PROXMOX_TOKEN_ID`
- `PROXMOX_TOKEN_SECRET`
- `PROXMOX_NODE`
- `PROXMOX_VMID`
- `PROXMOX_SNAPSHOT`

Para **Hyper-V (Windows host local)**:
- `HYPERV_VM_NAME` - nome exato da VM (ex.: `MalwareSandbox` se usar `_Config.ps1`, ou `win-sandbox` se criou manualmente)
- `HYPERV_SNAPSHOT_NAME` - checkpoint limpo (ex.: `CleanState` ou `clean-snap`)

Comum aos dois drivers HTTP:
- `VM_AGENT_BASE_URL` - URL do VM Agent (ex.: `http://192.168.100.10:5000`)
- `VM_AGENT_TOKEN` - token partilhado; o backend envia `X-Agent-Token` e o agent **exige** no arranque (dev local: `VM_AGENT_ALLOW_INSECURE=1`)

Timeouts (opcionais):
- `SANDBOX_HTTP_TIMEOUT_SECONDS` - pedidos HTTP ao agent
- `SANDBOX_BOOT_WAIT_SECONDS` / `SANDBOX_AGENT_WAIT_SECONDS` - espera após start da VM
- `SANDBOX_DYNAMIC_TIMEOUT_SECONDS` - timeout da execução na VM
- `SANDBOX_VM_OP_TIMEOUT_SECONDS` - restore/start Hyper-V via PowerShell (default **120**)

## VM Agent HTTP (implementado)

O **Caminho A** usa o agente em [`vm-agent/`](../vm-agent/README.md) - minimal API .NET 8 que corre **dentro da VM**
Windows guest, em rede isolada. Endpoints:

- `GET /api/health` - healthcheck
- `POST /api/upload` - recebe a amostra (campo `file`)
- `POST /api/run` - executa com timeout (`{"timeoutSeconds": 300}`)
- `GET /api/report` - JSON comportamental da última execução

**Estado atual da monitorização:** o agent regista `exitCode`, `stdout` e `stderr`; o campo
`monitoring` devolve `"not_implemented"` e as listas (`processes`, `fileSystem`, `registry`, `network`, …)
estão vazias até integração futura de Sysmon/ETW. Para telemetria completa de disco/registry/rede, use o
**Caminho B** ([`scripts/hyperv-sandbox/`](../scripts/hyperv-sandbox/README.md)).

O backend (drivers `hyperv`/`proxmox`):

- Restaura snapshot limpo antes/depois de cada job.
- Envia `X-Agent-Token` quando `VM_AGENT_TOKEN` está definido no host.

### Configuração e arranque na VM

```powershell
cd C:\vm-agent
dotnet build -c Release

# Obrigatório - o processo termina se VM_AGENT_TOKEN estiver vazio
$env:VM_AGENT_TOKEN = "seu-token-secreto"

# Bind apenas ao IP interno da VM - NÃO use 0.0.0.0 em produção
dotnet run --urls http://192.168.100.10:5000
```

> Em desenvolvimento local apenas: `$env:VM_AGENT_ALLOW_INSECURE = "1"` permite arrancar sem token (API aberta na rede da VM).

E configure no host:

- `VM_AGENT_BASE_URL=http://192.168.100.10:5000`
- `VM_AGENT_TOKEN=<mesmo token>`
- `SANDBOX_VM_DRIVER=hyperv`

Quando adicionar Sysmon/ETW/hooking, basta preencher as listas no JSON de `/api/report` - o backend já está
preparado para guardar esse objeto em `dynamicReport` e enviá-lo para o frontend.

---

## Guia manual Hyper-V (Caminho A - VM Agent)

> **Alternativa automatizada (Caminho B):** use `scripts/hyperv-sandbox/01-Setup-MalwareSandbox.ps1`
> que cria `MalwareSandbox` em `D:\PROJETOVM` com **Gen1** e snapshot `CleanState`.
> O guia abaixo descreve criação **manual** de uma VM (exemplo Gen2 `win-sandbox`) para o driver `hyperv` + VM Agent.

Este guia descreve passos para ter uma VM Windows isolada (sem internet) no
Hyper-V, pronta para análise dinâmica com o driver `hyperv` e o **VM Agent HTTP**.

### Pré-requisitos

- Windows 10 Pro/Enterprise ou Windows 11 Pro/Enterprise (ou Windows Server) com Hyper-V disponível.
- Permissões de administrador no PC.
- Espaço em disco livre (recomendado: pelo menos 80 GB para a VM + espaço para o ISO do Windows).
- Ficheiro ISO do Windows (10 ou 11). **Sandbox Hyper-V unattended:** ISO **en-US** (English United States) apenas - ver [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) e `_Config.ps1`.

---

### 1. Ativar o Hyper-V

Abra **PowerShell como Administrador** e execute:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

- `-Online` - aplica à instalação Windows atual.
- `-FeatureName Microsoft-Hyper-V` - ativa o papel Hyper-V.
- `-All` - inclui subfuncionalidades (Hyper-V Platform, Hyper-V Management Tools, etc.).

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

- `-Name "SandboxSwitch"` - nome do switch (pode usar outro; terá de o referir ao criar a VM).
- `-SwitchType Internal` - rede interna: VM e host partilham um segmento lógico; não há bridge para o adaptador físico nem NAT por defeito.

Opcional: atribuir um endereço ao adaptador virtual do host neste switch, para a VM conseguir falar com o
host (e o backend) por IP fixo. Por exemplo, rede `192.168.100.0/24`:

```powershell
Get-NetAdapter | Where-Object { $_.Name -like "*SandboxSwitch*" } | ForEach-Object {
    New-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress 192.168.100.1 -PrefixLength 24
}
```

Assim, dentro da VM pode configurar, por exemplo, `192.168.100.10` com gateway `192.168.100.1`; o backend
no host usará `VM_AGENT_BASE_URL=http://192.168.100.10:5000`.

No **Caminho B** (scripts `hyperv-sandbox/`), o setup (`01-Setup-MalwareSandbox.ps1` / `Setup/Phase4-Switch.ps1`)
cria também a regra de firewall `PROJETOVM Block inbound from sandbox` que bloqueia tráfego inbound do segmento
`192.168.100.0/24` para o host. Cada run do `04-Run-Sample.ps1` revalida que a VM só tem adaptadores no switch Internal.

---

### 3. Criar a pasta para os ficheiros da VM

Escolha um disco com espaço (ex.: `D:`). Crie pastas para o disco virtual e, se desejar, para ISOs:

```powershell
New-Item -ItemType Directory -Path "D:\VMs" -Force
New-Item -ItemType Directory -Path "D:\VMs\win-sandbox" -Force
New-Item -ItemType Directory -Path "D:\ISOs" -Force
```

Coloque o ISO do Windows em `D:\ISOs\`, por exemplo `Win10_22H2.iso`. Ajuste o caminho nos comandos abaixo
se utilizar outro nome ou localização.

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

- `-Name` - nome da VM (será o `HYPERV_VM_NAME`).
- `-Generation 2` - VM UEFI (Secure Boot, etc.).
- `-MemoryStartupBytes 4GB` - RAM inicial (pode aumentar para 8 GB se dispuser de recursos).
- `-SwitchName` - switch criado no passo 2 (rede isolada).
- `-Path` - pasta de configuração da VM.
- `-NewVHDPath` - caminho do disco virtual (será criado automaticamente).
- `-NewVHDSizeBytes 80GB` - tamanho do disco (ajusta se precisares).

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

- `Add-VMDvdDrive` - associa o ISO como drive de DVD.
- `Set-VMFirmware -FirstBootDevice $dvd` - a VM arranca primeiro pelo DVD (para instalar o Windows).

---

### 7. Arrancar a VM e instalar o Windows

```powershell
Start-VM -Name $VMName
```

Abra o **Hyper-V Manager** (opcional): `virtmgmt.msc`, ligue-se à VM e abra *Connect* para ver o ecrã da VM.

- Arranque a partir do DVD e complete a instalação do Windows (idioma, partição única, conta local ou sem conta, etc.).
- Quando o Windows estiver no ambiente de trabalho, **desliga a VM** antes de criar o checkpoint (opcional mas recomendado para snapshot limpo):

```powershell
Stop-VM -Name $VMName -Force
```

---

### 8. Configurar a rede dentro da VM (IP estático)

Ligue novamente a VM e entre na consola:

```powershell
Start-VM -Name $VMName
```

Dentro da VM (Windows):

1. Abra **Definições → Rede e Internet → Ethernet** (ou o adaptador ligado ao switch interno).
2. **Editar** em «Atribuição de endereço IP» → **Manual**.
3. Active **IPv4** e defina, por exemplo:
   - Endereço IP: `192.168.100.10`
   - Máscara: `255.255.255.0`
   - Gateway: `192.168.100.1` (IP do host no switch; pode ficar vazio se não precisar de gateway).
   - DNS: deixe vazio ou `127.0.0.1` - a VM não deve resolver domínios na Internet.

Guarde. A VM fica com IP fixo na rede interna; **sem gateway/DNS útil, não há Internet**.

---

### 9. Instalar o VM Agent dentro da VM

Dentro da VM:

1. Copia para a VM a pasta **`vm-agent`** do teu projeto (pen USB, partilha de pasta do Hyper-V, ou outro método).
   - Por exemplo, coloca em `C:\vm-agent\`.
2. Abra **PowerShell** ou **Cmd** como utilizador normal (não é necessário administrador para correr o agent).
3. Instale .NET 8 SDK se ainda não estiver instalado (https://dotnet.microsoft.com/download/dotnet/8.0 - pode transferir o instalador no host e copiá-lo para a VM).
4. Na pasta do agent:

```powershell
dotnet run --urls http://192.168.100.10:5000
```

(Com `$env:VM_AGENT_TOKEN` definido - ver seção VM Agent acima.)

O agent escuta no IP configurado. No host:

```powershell
$env:VM_AGENT_TOKEN = "<mesmo token>"
Invoke-RestMethod -Uri "http://192.168.100.10:5000/api/health" -Headers @{ "X-Agent-Token" = $env:VM_AGENT_TOKEN }
```

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
$env:VM_AGENT_TOKEN = "seu-token-secreto"

cd backend
uvicorn api:app --reload --host 127.0.0.1 --port 8000
```

Ajuste `VM_AGENT_BASE_URL` se utilizou outro IP na VM.

---

### 12. Uso na webapp (drag-and-drop)

1. Arranque o frontend (`npm run dev` em `frontend` - **http://localhost:8080**).
2. Escolha **«Apenas dinâmica»** ou **«Ambas»**.
3. Faça upload do ficheiro (drag-and-drop ou seleção).

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
