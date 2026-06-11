# Sandbox Hyper-V — análise comportamental (COM1 + Copy-VMFile)

Ambiente isolado para análise comportamental de malware: VM Hyper-V **sem internet**, snapshot limpo, execução da amostra **dentro da VM** e recolha do relatório no host.

> **Auditoria (Jun 2026):** isolamento de rede por run, credenciais sem fallback inseguro, cleanup `try/finally` — [`docs/AUDITORIA.md`](../../docs/AUDITORIA.md).

Este pipeline é usado pela **app desktop WPF** (`wpf-gui`) e pode ser executado **manualmente** no host. **Não** é invocado pelo backend Python — ver [Dois caminhos de análise dinâmica](#dois-caminhos-de-análise-dinâmica) abaixo.

## Transporte de relatórios (implementação actual)

O `04-Run-Sample.ps1` **sempre**:

1. Arranca um job em background que escuta o **Named Pipe** ligado ao **COM1** da VM (VM **Generation 1**).
2. Executa a análise na VM; o guest envia o relatório **linha-a-linha** (`START_OF_REPORT` … `END_OF_REPORT`) via `vm/Send-ReportViaCom.ps1`.
3. Se o pipe falhar ou expirar, recorre ao **Copy-VMFile** (Guest Service Interface, activado só durante o run) para ler `C:\analysis.txt` ou artefactos em `D:\PROJETOVM\Reports\`.

> **Nota:** Não existe parâmetro `-ReportTransport` nem variável `PROJETOVM_ReportTransport` no código actual. O protocolo binário **SBXREP1** (`FILE …`) descrito em versões antigas da documentação **não está implementado** — ver [`SERIAL_REPORT_PROTOCOL.md`](SERIAL_REPORT_PROTOCOL.md).

- **Pasta base:** `D:\PROJETOVM` (VM, Reports, Samples, Logs) — configurável em `_Config.ps1`.
- **VM:** `MalwareSandbox` · **Snapshot:** `CleanState` · **Switch:** `SandboxSwitch` (Internal).
- **Fluxo:** restore snapshot → start VM → copiar amostra/scripts → executar na VM → relatório por pipe (+ fallback Copy-VMFile) → stop VM → restore snapshot.

## Dois caminhos de análise dinâmica

| | **A — Backend + VM Agent (HTTP)** | **B — Scripts PowerShell (este README)** |
|---|-----------------------------------|------------------------------------------|
| **Quem orquestra** | `backend/vm_orchestrator.py` + driver `hyperv` | WPF ou `04-Run-Sample.ps1` manual |
| **Comunicação** | HTTP para `vm-agent` (`/api/upload`, `/api/run`, `/api/report`) | COM1 → Named Pipe + Copy-VMFile |
| **Config** | Env vars (`HYPERV_VM_NAME`, `VM_AGENT_BASE_URL`, …) | `_Config.ps1` (`D:\PROJETOVM`, …) |
| **Documentação** | [`docs/sandbox-hyperv-setup.md`](../../docs/sandbox-hyperv-setup.md) (Caminho A) | Este ficheiro (Caminho B) |

Os dois caminhos são **independentes**. Podem partilhar a mesma VM física se os nomes/snapshot coincidirem, mas normalmente usa-se **ou** o agent HTTP **ou** o pipeline serial.

## Convenções dos scripts

- Ficheiros `.ps1`: **UTF-8 com BOM**, fim de linha **CRLF** (ver [`docs/ps1-scripts.md`](../../docs/ps1-scripts.md)).
- Mensagens ao utilizador em **português** com acentos; identificadores de funções em inglês.
- CI valida UTF-8: `python scripts/ci/check_ps1_utf8.py`.

## Pré-requisitos

- Windows 10/11 Pro ou Enterprise (ou Server) com **Hyper-V**.
- PowerShell **como Administrador** para setup e orquestração.
- **ISO Windows en-US** (English United States) — necessário para instalação unattended.
- VM **Generation 1** (BIOS) para COM1/pipe — definido em `_Config.ps1` (`PROJETOVM_VMGeneration = 1`).

## Estrutura de ficheiros

```
scripts/hyperv-sandbox/
├── _Config.ps1                      # Config central (paths, VM, snapshot, credenciais guest)
├── SandboxCommon.psm1               # Módulo agregador (SandboxCommon/*.ps1)
├── 00-Reset-Sandbox.ps1             # Repõe sandbox (confirmação SIM)
├── 01-Setup-MalwareSandbox.ps1      # Setup único (pastas, VM, switch, snapshot)
├── 04-Run-Sample.ps1                # Orquestra uma análise (try/finally de cleanup)
├── RunSample/                       # Fases A–G do 04
├── SandboxCommon/                   # Logging, pipe, VM, ficheiros, …
├── vm/                              # Scripts executados DENTRO da VM
│   ├── Run-MalwareAnalysis.ps1
│   └── Send-ReportViaCom.ps1        # Envio linha-a-linha pelo COM1
├── SERIAL_REPORT_PROTOCOL.md        # Protocolo real (START_OF_REPORT)
└── README.md
```

## Configuração (`_Config.ps1` e variáveis de ambiente)

| Variável | Default / origem | Descrição |
|----------|------------------|-----------|
| `PROJETOVM_BasePath` | `D:\PROJETOVM` | Pasta raiz (override: env `PROJETOVM_BasePath`) |
| `PROJETOVM_VMName` | `MalwareSandbox` | Nome da VM |
| `PROJETOVM_SnapshotName` | `CleanState` | Snapshot limpo |
| `PROJETOVM_SwitchName` | `SandboxSwitch` | Switch Internal |
| `PROJETOVM_VMGeneration` | `1` | Gen1 para COM1 |
| `PROJETOVM_GuestUser` | `analyst` | Utilizador guest (override: env `PROJETOVM_GuestUser`) |
| `PROJETOVM_GuestPassword` | *(obrigatório)* | **Obrigatória** via env. Dev: `PROJETOVM_ALLOW_INSECURE_DEFAULTS=1` usa password de exemplo. |

## Instalação (fazer uma vez)

1. PowerShell **como Administrador**:
   ```powershell
   cd "<RAIZ-DO-REPO>\scripts\hyperv-sandbox"
   .\01-Setup-MalwareSandbox.ps1
   ```
2. Instale o Windows na VM; conclua o first-time setup (`05-FirstTimeVmSetup.ps1` se aplicável).
3. Desligue a VM e confirme o snapshot `CleanState`.

## Utilização

### Executar uma amostra

```powershell
cd "<RAIZ-DO-REPO>\scripts\hyperv-sandbox"
.\04-Run-Sample.ps1 -SamplePath "D:\PROJETOVM\Samples\suspeito.exe" -TimeoutSeconds 120
```

| Parâmetro | Descrição |
|-----------|-----------|
| `-SamplePath` | Caminho no **host** do `.exe`. Se omitido, usa o `.exe`/`.dll` mais recente em `Samples\`. |
| `-AllowAutoSample` | Se não houver amostra em `Samples\`, gera `sample_autogen.exe` inofensivo (apenas dev/teste). |
| `-TimeoutSeconds` | Timeout da execução **dentro da VM** (default 120). |
| `-GlobalTimeoutSeconds` | Deadline global do run no host (default 600). |
| `-BootWaitSeconds` | Reservado / margem de arranque (ver fases). |

Relatório: `D:\PROJETOVM\Reports\analysis_<RunId>.txt` · Logs: `D:\PROJETOVM\Logs\Runs\<RunId>\`.

### Cleanup em falha

O `04-Run-Sample.ps1` envolve as fases num `try/finally`: se o run falhar a meio, tenta parar a VM, restaurar o snapshot, desactivar o Guest Service e parar o job do pipe.

## Conteúdo do relatório

Gerado por `vm/Run-MalwareAnalysis.ps1` dentro da VM:

- Alterações em ficheiros, registry, processos, rede (TCP), serviços, tarefas agendadas.
- Para telemetria avançada (Sysmon/ETW), instale Sysmon na VM (`03-Install-SysmonInGuest.ps1`).

## Segurança

- VM em switch **Internal** — sem internet por defeito.
- **Preflight de rede** em cada run (`Assert-SandboxVmNetworkIsolation` em `RunSample/PhaseA-Setup.ps1`): falha se existir adaptador fora do switch Internal esperado.
- **Firewall no host** (`Ensure-SandboxHostFirewall`): bloqueia inbound de `192.168.100.0/24` no adaptador do switch (criado no setup e ao atribuir IP).
- Snapshot limpo antes/depois de cada análise; `04-Run-Sample.ps1` com `try/finally` e `PhaseG-Finish.ps1`.
- Guest Service Interface activado **apenas** durante o `04`; desactivado no fim.
- **Não** versionar passwords reais — `PROJETOVM_GuestPassword` obrigatória em produção.
- Evitar Enhanced Session / clipboard partilhado durante runs de malware.
- `tools/winutil.ps1` **não** está no repositório (script de terceiros); transferir localmente só se necessário.

## Integração com o backend

O driver `backend/vm_drivers/hyperv.py` **não** executa `04-Run-Sample.ps1`. Usa **VM Agent HTTP** (`vm-agent/`) com restore/start via PowerShell e pedidos a `/api/upload`, `/api/run`, `/api/report`. Para integrar os scripts PowerShell no backend seria necessário um wrapper Python (não implementado).
