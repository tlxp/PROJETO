# VM Agent - RAT Analyzer

Agente HTTP **minimal API** (.NET 8) que corre **dentro da VM Windows** da sandbox. Recebe amostras, executa-as com timeout e devolve relatório comportamental em JSON. Usado pelo **Caminho A** (`backend/vm_orchestrator.py` + driver `hyperv` ou `proxmox`).

> **Não confundir** com o pipeline PowerShell Hyper-V (`04-Run-Sample.ps1` / **Caminho B**), que não usa este agente.

Escolha A vs B: [`docs/README.md`](../docs/README.md#análise-dinâmica--qual-caminho-usar) · setup Hyper-V: [`docs/sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md).

## Índice

- [Requisitos](#requisitos)
- [Arranque na VM](#arranque-na-vm)
- [Configuração no host](#configuração-no-host)
- [Endpoints](#endpoints)
- [Fluxo típico (HTTP)](#fluxo-típico-http)
- [Formato de `/api/report`](#formato-de-apireport-estado-atual)
- [Códigos de resposta](#códigos-de-resposta)
- [Segurança](#segurança)
- [Limitações e roadmap](#limitações-e-roadmap)
- [Resolução de problemas](#resolução-de-problemas)

## Requisitos

- **Windows** na VM guest (sandbox isolada).
- **.NET 8 Runtime** ou SDK.
- Rede interna host↔VM (ex.: `192.168.100.0/24`); **sem** exposição à Internet.
- `VM_AGENT_TOKEN` no arranque (obrigatório em produção).

## Arranque na VM

```powershell
cd C:\vm-agent
dotnet build -c Release

# Obrigatório - o processo termina sem token (exceto dev com VM_AGENT_ALLOW_INSECURE=1)
$env:VM_AGENT_TOKEN = "<token-partilhado-com-o-backend>"

# Bind apenas ao IP interno da VM - NÃO use 0.0.0.0 em produção
dotnet run --urls http://192.168.100.10:5000
```

Publicação autónoma:

```powershell
dotnet publish -c Release -r win-x64
.\bin\Release\net8.0\win-x64\publish\VmAgent.exe --urls http://192.168.100.10:5000
```

Amostras gravadas em `samples/` (relativo ao diretório do executável). Novo upload faz `Reset()` do estado anterior.

## Configuração no host

```powershell
$env:SANDBOX_VM_DRIVER = "hyperv"
$env:HYPERV_VM_NAME = "win-sandbox"          # ou MalwareSandbox se partilhar _Config.ps1
$env:HYPERV_SNAPSHOT_NAME = "clean-snap"     # ou CleanState
$env:VM_AGENT_BASE_URL = "http://192.168.100.10:5000"
$env:VM_AGENT_TOKEN = "<mesmo token>"
```

Segredos: [`docs/production-secrets.md`](../docs/production-secrets.md). Driver `proxmox`: experimental - ver nota em [`docs/README.md`](../docs/README.md).

## Endpoints

Todas as rotas exigem header **`X-Agent-Token`** = `VM_AGENT_TOKEN` (exceto `VM_AGENT_ALLOW_INSECURE=1` em dev).

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/health` | `{ "status": "ok", "component": "vm-agent" }` |
| `POST` | `/api/upload` | `multipart/form-data`, campo `file` - grava em `samples/` (máx. **200 MB**) |
| `POST` | `/api/run` | Body JSON: `{ "timeoutSeconds": 300 }` (máx. **600** s). Uma execução de cada vez. |
| `GET` | `/api/report` | JSON comportamental da última execução |

## Fluxo típico (HTTP)

```powershell
$headers = @{ "X-Agent-Token" = $env:VM_AGENT_TOKEN }

# 1) Health
Invoke-RestMethod -Uri "$base/api/health" -Headers $headers

# 2) Upload
$form = @{ file = Get-Item "C:\samples\test.exe" }
Invoke-RestMethod -Uri "$base/api/upload" -Method Post -Headers $headers -Form $form

# 3) Run
Invoke-RestMethod -Uri "$base/api/run" -Method Post -Headers $headers `
  -ContentType "application/json" -Body '{"timeoutSeconds":120}'

# 4) Report
Invoke-RestMethod -Uri "$base/api/report" -Headers $headers
```

Via backend: `POST /api/analysis?analysis_type=dynamic` - o orquestrador executa upload → run → report e guarda em `dynamicReport`.

Smoke test inofensivo: [`benign-vm-test`](../benign-vm-test/README.md) (validação completa de telemetria apenas no **Caminho B**).

## Formato de `/api/report` (estado atual)

```json
{
  "status": "finished",
  "startedAt": "2026-06-15T12:00:00.0000000Z",
  "finishedAt": "2026-06-15T12:00:05.0000000Z",
  "fileName": "BenignVmTest.exe",
  "exitCode": 0,
  "stdout": "[benign-vm-test] início\n…",
  "stderr": "",
  "monitoring": "not_implemented",
  "processes": [],
  "fileSystem": [],
  "registry": [],
  "network": [],
  "mutexes": [],
  "persistence": [],
  "privilegeEscalation": [],
  "sensitiveApiCalls": []
}
```

`status` pode ser `running`, `finished` ou `timeout`. O backend persiste o objeto em `dynamicReport` para o frontend.

## Códigos de resposta

| Código | Quando |
|--------|--------|
| **401** | `X-Agent-Token` em falta ou inválido |
| **400** | Upload sem `file`, nome inválido, `/api/report` sem execução prévia |
| **409** | `/api/run` com execução já em curso |
| **413** | Upload > 200 MB |

`stdout`/`stderr` limitados a **1 MB** cada na captura.

## Segurança

Arquitetura completa: [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) · segredos: [`docs/production-secrets.md`](../docs/production-secrets.md).

| Regra | Detalhe |
|-------|---------|
| Token obrigatório | Sem `VM_AGENT_TOKEN`, o processo **termina** (exceto `VM_AGENT_ALLOW_INSECURE=1`) |
| Comparação segura | Header `X-Agent-Token` validado em tempo constante |
| Bind restrito | IP interno da VM; evitar `0.0.0.0` ou WAN |
| Upload sanitizado | Apenas nome de ficheiro; destino restrito a `samples/` |
| Execução única | `RunGate` - uma run por instância |
| Snapshot | Host restaura checkpoint limpo - o agent **não** gere snapshots |

## Limitações e roadmap

- **Monitorização:** apenas `exitCode`, `stdout`, `stderr`; listas de processos/ficheiros/registry/rede reservadas para Sysmon/ETW futuro.
- **Persistência:** estado em memória; novo upload limpa execução anterior.
- **Telemetria completa:** use **Caminho B** - [`scripts/hyperv-sandbox/`](../scripts/hyperv-sandbox/README.md).

## Resolução de problemas

| Sintoma | Ação |
|---------|-------|
| Processo termina ao arrancar | Definir `VM_AGENT_TOKEN` ou `VM_AGENT_ALLOW_INSECURE=1` (só dev) |
| Backend health check falha | Token igual host/VM; IP estático; firewall na rede Internal |
| `dynamicReport` com listas vazias | Esperado no Caminho A - usar Caminho B para telemetria |
| Timeout na execução | Aumentar `timeoutSeconds` (máx. 600) ou `SANDBOX_DYNAMIC_TIMEOUT_SECONDS` no host |
| Driver hyperv não restaura VM | `HYPERV_VM_NAME` / `HYPERV_SNAPSHOT_NAME` corretos - [`sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md) |

## Estrutura

```
vm-agent/
├── Program.cs                 # Arranque Minimal API
├── Configuration/AgentLimits.cs
├── Endpoints/AgentEndpoints.cs
├── Models/RunRequest.cs
├── Security/                  # Token auth + comparação em tempo constante
├── Services/                  # Upload, execução de amostras
└── State/                     # AnalysisState, RunGate
```

## Testes

Testes unitários e de integração HTTP em `VmAgent.Tests/` (xUnit):

```powershell
dotnet test vm-agent/VmAgent.Tests/VmAgent.Tests.csproj -c Release
```

Cobertura: autenticação por token, uploads, `SampleStorage`, `SampleRunner`, endpoints `/api/*`.

Parte de `RatAnalyzer.sln`. CI: `dotnet test RatAnalyzer.sln -c Release`.
