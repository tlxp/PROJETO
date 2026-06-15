# Sandbox Hyper-V - análise comportamental (PsDirect + SHA256)

Ambiente isolado para análise comportamental de malware: VM Hyper-V **sem internet**, snapshot limpo, execução da amostra **dentro da VM** e recolha do relatório no host.

Este pipeline é usado pela **app WPF** ([`wpf-gui/README.md`](../../wpf-gui/README.md)) ou manualmente no host. **Não** é invocado pelo backend Python. Caminho A (HTTP): [`docs/sandbox-hyperv-setup.md`](../../docs/sandbox-hyperv-setup.md) · índice: [`docs/README.md`](../../docs/README.md).

> **Transporte de relatório:** cópia guest→host via PsDirect / Copy-VMFile, com verificação SHA256 após a cópia. Detalhe: [`SERIAL_REPORT_PROTOCOL.md`](SERIAL_REPORT_PROTOCOL.md).

## Resumo rápido

1. **Uma vez:** `01-Setup-MalwareSandbox.ps1` → VM `MalwareSandbox`, snapshot `CleanState`, switch Internal.
2. **First-time:** instalar Windows na VM; `05-FirstTimeVmSetup.ps1` (runtimes em [`offline/runtimes/`](offline/runtimes/README.md), Sysmon opcional).
3. **Por análise:** `04-Run-Sample.ps1 -SamplePath <amostra.exe>` (PowerShell como Administrador).
4. Relatório em `D:\PROJETOVM\Reports\`; validação com [`benign-vm-test`](../../benign-vm-test/README.md).

Variáveis obrigatórias em produção: `PROJETOVM_GuestPassword` - ver [`docs/production-secrets.md`](../../docs/production-secrets.md).

## Transporte de relatórios (implementação atual)

O `04-Run-Sample.ps1`:

1. Executa a análise na VM (`Run-MalwareAnalysis.ps1` em processo destacado).
2. Aguarda `guest_analysis_done.txt` ou marcador `REPORT_END;` em `C:\analysis.txt`.
3. Copia `C:\analysis.txt` para o host via **PsDirect** ou **Copy-VMFile** (Guest Services).
4. **Verifica SHA256** (e tamanho) do ficheiro copiado contra o digest registado no guest.

- **Pasta base:** `D:\PROJETOVM` (VM, Reports, Samples, Logs) - configurável em `_Config.ps1`.
- **VM:** `MalwareSandbox` · **Snapshot:** `CleanState` · **Switch:** `SandboxSwitch` (Internal).
- **Fluxo:** restore snapshot → start VM → copiar amostra/scripts → executar na VM → copiar relatório + validar hash → stop VM → restore snapshot.

## Convenções dos scripts

- Ficheiros `.ps1`: **UTF-8 com BOM**, fim de linha **CRLF** (ver [`docs/ps1-scripts.md`](../../docs/ps1-scripts.md)).
- Mensagens ao utilizador em **português** com acentos; identificadores de funções em inglês.
- CI valida UTF-8: `python scripts/ci/check_ps1_utf8.py`.

## Pré-requisitos

- Windows 10/11 Pro ou Enterprise (ou Server) com **Hyper-V**.
- PowerShell **como Administrador** para setup e orquestração.
- **ISO Windows en-US** (English United States) - necessário para instalação unattended.
- VM **Generation 1 ou 2** (o setup default em `_Config.ps1` é Gen1; PsDirect funciona em ambas).

## Estrutura de ficheiros

```
scripts/hyperv-sandbox/
├── _Config.ps1                      # Config central (paths, VM, snapshot, credenciais guest)
├── SandboxCommon.psm1               # Módulo agregador (SandboxCommon/*.ps1)
├── 00-Reset-Sandbox.ps1             # Repõe sandbox (confirmação SIM)
├── 01-Setup-MalwareSandbox.ps1      # Setup único (pastas, VM, switch, snapshot)
├── 02-Host-ReceiveReport.ps1        # Legado COM1/pipe (debug; não usado pelo 04)
├── 03-Install-SysmonInGuest.ps1     # Instala Sysmon na VM e atualiza CleanState
├── 04-Run-Sample.ps1                # Orquestra uma análise (try/finally de cleanup)
├── 05-FirstTimeVmSetup.ps1          # Setup inicial na VM (runtimes, Sysmon opcional)
├── 06-Prepare-GuestDependencies.ps1 # Prepara instaladores offline no host/VM (sem internet)
├── 07-Ensure-Runtimes.ps1           # Garante VC++/NET Desktop na VM a partir de offline/runtimes/
├── RunSample/                       # Fases A-G do 04
├── FirstTimeVmSetup/                # Fases do 05
├── EnsureRuntimes/                  # Fases do 07
├── PrepareGuestDependencies/        # Fases do 06
├── offline/runtimes/                # Instaladores offline (ver README na pasta)
├── SandboxCommon/                   # Logging, VM, transferência de ficheiros, …
├── vm/                              # Scripts executados DENTRO da VM
│   └── Run-MalwareAnalysis.ps1
├── SERIAL_REPORT_PROTOCOL.md        # PsDirect + SHA256 (histórico COM1 no mesmo doc)
├── TROUBLESHOOTING.md               # Resolução de problemas operacionais
└── README.md
```

### Scripts numerados (`00`-`07`)

| Script | Quando usar |
|--------|-------------|
| `00-Reset-Sandbox.ps1` | Repor VM ao snapshot limpo após run incompleto ou estado inconsistente |
| `01-Setup-MalwareSandbox.ps1` | **Uma vez** - criar pastas, VM, switch Internal, snapshot inicial |
| `02-Host-ReceiveReport.ps1` | **Legado** - receptor COM1/pipe manual (não usado pelo `04`) |
| `03-Install-SysmonInGuest.ps1` | Instalar Sysmon na VM guest (também via fase `FirstTimeVmSetup/PhaseE2-Sysmon.ps1`) |
| `04-Run-Sample.ps1` | **Por análise** - pipeline completo (WPF ou linha de comandos) |
| `05-FirstTimeVmSetup.ps1` | **Uma vez** após instalar Windows - runtimes, dependências, snapshot `CleanState` |
| `06-Prepare-GuestDependencies.ps1` | Preparar ferramentas offline no host para runs sem internet na VM |
| `07-Ensure-Runtimes.ps1` | Garantir VC++ e .NET Desktop na VM a partir de `offline/runtimes/` |

## Configuração (`_Config.ps1` e variáveis de ambiente)

| Variável | Default / origem | Descrição |
|----------|------------------|-----------|
| `PROJETOVM_BasePath` | `D:\PROJETOVM` | Pasta raiz (override: env `PROJETOVM_BasePath`) |
| `PROJETOVM_VMName` | `MalwareSandbox` | Nome da VM |
| `PROJETOVM_SnapshotName` | `CleanState` | Snapshot limpo |
| `PROJETOVM_SwitchName` | `SandboxSwitch` | Switch Internal |
| `PROJETOVM_VMGeneration` | `1` | Gen1 (default) ou Gen2 |
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
| `-GlobalTimeoutSeconds` | Deadline global do run no host (default 900; estendido automaticamente para amostras grandes). |
| `-BootWaitSeconds` | Reservado / margem de arranque (ver fases). |

Relatório: `D:\PROJETOVM\Reports\analysis_<RunId>.txt` · Logs: `D:\PROJETOVM\Logs\Runs\<RunId>\`.

Problemas comuns: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

### Cleanup em falha

O `04-Run-Sample.ps1` envolve as fases num `try/finally`: se o run falhar a meio, tenta parar a VM, restaurar o snapshot e desativar o Guest Service.

## Conteúdo do relatório

Gerado por `vm/Run-MalwareAnalysis.ps1` dentro da VM:

- Alterações em ficheiros, registry, processos, rede (TCP), serviços, tarefas agendadas.
- Para telemetria avançada (Sysmon/ETW), instale Sysmon na VM (`03-Install-SysmonInGuest.ps1` ou fase `FirstTimeVmSetup/PhaseE2-Sysmon.ps1` no setup inicial).

## Segurança

Arquitetura completa: [`docs/SEGURANCA.md`](../../docs/SEGURANCA.md) · segredos: [`docs/production-secrets.md`](../../docs/production-secrets.md).

- VM em switch **Internal** - sem internet por defeito.
- **Preflight de rede** em cada run (`Assert-SandboxVmNetworkIsolation` em `RunSample/PhaseA-Setup.ps1`): falha se existir adaptador fora do switch Internal esperado.
- **Firewall no host** (`Ensure-SandboxHostFirewall`): bloqueia inbound de `192.168.100.0/24` no adaptador do switch (criado no setup e ao atribuir IP).
- Snapshot limpo antes/depois de cada análise; `04-Run-Sample.ps1` com `try/finally` e `PhaseG-Finish.ps1`.
- **Verificação SHA256** do relatório após cópia guest→host.
- Guest Service Interface ativado **apenas** durante o `04`; desativado no fim.
- **Não** versionar passwords reais - `PROJETOVM_GuestPassword` obrigatória em produção.
- Evitar Enhanced Session / clipboard partilhado durante runs de malware.
- `tools/winutil.ps1` **não** está no repositório (script de terceiros); transferir localmente só se necessário.

## Integração com o backend

O driver `hyperv.py` usa **vm-agent HTTP**, não este pipeline. Índice dos caminhos: [`docs/README.md`](../../docs/README.md).
