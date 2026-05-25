# Sandbox Hyper-V — análise comportamental (Guest Service + COM1 opcional)

Ambiente isolado para análise comportamental de malware: VM Hyper-V sem internet, snapshot limpo. Por defeito (**`_Config.ps1`:** `GuestService`) o relatório chega só por **Copy-VMFile**. Para **COM1 → Named Pipe** (SBXREP1), use `-ReportTransport Both` ou `Serial`, ou defina `PROJETOVM_ReportTransport` em `_Config.ps1`.

- **Pasta base:** `D:\PROJETOVM` (VM, Reports, Samples, Logs).
- **Fluxo:** criar VM (Gen1 recomendada para COM1) → colocar .exe/.dll → executar na VM → monitorizar alterações → relatório em terceira pessoa → recolher no host por **pipe serial** e/ou **Copy-VMFile** nos caminhos de `D:\PROJETOVM\Reports\` → restaurar snapshot → encerrar VM.

## Pré-requisitos

- Windows 10/11 Pro ou Enterprise (ou Server) com **Hyper-V**.
- PowerShell **como Administrador** para setup e orquestração.
- **ISO do Windows:** **en-US** (English United States) apenas — mais nada é suportado para instalação unattended.
- VM com Windows instalada; **COM1/pipe** exige **VM Generation 1** (definido em `_Config.ps1`). Em Gen2 o `04` usa automaticamente só Guest Service.

## Estrutura de ficheiros

```
scripts/hyperv-sandbox/
├── _Config.ps1                  # Configuração central (D:\PROJETOVM, VM, snapshot)
├── 01-Setup-MalwareSandbox.ps1  # Setup único: pastas, VM, switch, IP host, snapshot
├── 03-Install-SysmonInGuest.ps1 # Host: instala Sysmon dentro da VM (após Windows instalado)
├── 04-Run-Sample.ps1            # Host: orquestração (restore, COM1+pipe por run, start, copy, run, relatórios, restore)
├── SERIAL_REPORT_PROTOCOL.md    # Especificação SBXREP1 (COM1 / Named Pipe)
├── 05-FirstTimeVmSetup.ps1      # Host: primeira entrada — valida guest, garante isolamento e cria snapshot
├── vm/
│   ├── Prepare-RealisticEnvironment.ps1  # VM: prepara ambiente "realista" (sem instalar apps)
│   └── Run-MalwareAnalysis.ps1   # VM: baseline → executa sample → diff → relatório em C:\
└── README.md
```

## Estrutura em D:\PROJETOVM (após setup)

```
D:\PROJETOVM\
├── VM\           # Configuração da VM e Sandbox.vhdx
├── Reports\      # Relatórios de análise (.txt)
├── Samples\      # Amostras a analisar (.exe / .dll)
└── Logs\         # Logs de execução (opcional)
```

## Instalação (fazer uma vez)

1. Abra **PowerShell como Administrador**.
2. Navegue até à pasta dos scripts:
   ```powershell
   cd "C:\Users\jmigu\Desktop\PROJETO\PROJETO\scripts\hyperv-sandbox"
   ```
3. Execute o setup:
   ```powershell
   .\01-Setup-MalwareSandbox.ps1
   ```
   - Se o Hyper-V não estiver ativo, o script ativa-o e pede **reinício**; após reiniciar, execute o script novamente.
   - O script cria `D:\PROJETOVM`, a VM `MalwareSandbox`, o switch interno `SandboxSwitch`, atribui 192.168.100.1/24 ao adaptador do host (se existir), e cria o snapshot `CleanState` (se a VM estiver desligada).
   - Se a VM `MalwareSandbox` e/ou o VHDX `Sandbox.vhdx` já existirem, o script pergunta se quer **eliminar e reinstalar de raiz**.
   - Para reinstalar **sem pedir confirmação** (opção usada pela GUI quando deteta recursos existentes), execute:
     ```powershell
     .\01-Setup-MalwareSandbox.ps1 -ForceReinstall
     ```
   - Quando o setup é iniciado pela GUI WPF (`wpf-gui/Views/VmAnalysisWindow.xaml.cs`), é feita uma pré-checagem e é apresentado um pop-up para confirmar a reinstalação.
4. Instale o **Windows** na VM (ligar DVD/ISO, arrancar, concluir instalação).
5. Dentro da VM: desative rede pública; opcionalmente configure IP estático (ex.: 192.168.100.10/24, gateway 192.168.100.1).
6. (Opcional mas recomendado) Instale **Sysmon** na VM com configuração personalizada:
   ```powershell
   # No host, após o Windows estar instalado na VM e Sysmon existir em D:\Tools\Sysmon\
   cd "C:\Users\jmigu\Desktop\PROJETO\PROJETO\scripts\hyperv-sandbox"
   .\03-Install-SysmonInGuest.ps1 `
     -SysmonExePath "D:\Tools\Sysmon\Sysmon64.exe" `
     -SysmonConfigPath "D:\Tools\Sysmon\sysmon-config.xml"
   ```
7. (Opcional manual) copie para a VM o script da pasta `vm\` apenas se não usar apenas o `04-Run-Sample.ps1` para cópias:
   - `Run-MalwareAnalysis.ps1`
8. Desligue a VM e crie/atualize o snapshot limpo:
   ```powershell
   Stop-VM -Name MalwareSandbox -Force
   Checkpoint-VM -Name MalwareSandbox -SnapshotName CleanState
   ```

## Utilização

### Executar uma amostra (host)

Coloque o ficheiro suspeito em `D:\PROJETOVM\Samples\` (ou use outro caminho). No **host**, como Administrador:

```powershell
cd "C:\Users\jmigu\Desktop\PROJETO\PROJETO\scripts\hyperv-sandbox"
.\04-Run-Sample.ps1 -SamplePath "D:\PROJETOVM\Samples\suspeito.exe" -TimeoutSeconds 120
```

O relatório será guardado em `D:\PROJETOVM\Reports\analysis_<RunId>.txt` (e JSON/artefactos ao lado). O ficheiro `D:\PROJETOVM\Logs\Runs\<RunId>\run_<RunId>.json` regista `report_transport`, estado do pipe e caminhos.

**Transporte de relatórios:** por defeito só **Guest Service**. Para ativar COM1 + pipe: `-ReportTransport Both` (serial + cópia de refugo) ou `Serial`. Em `_Config.ps1`, `PROJETOVM_ReportTransport` pode fixar o modo por omissão.

```powershell
.\04-Run-Sample.ps1 -SamplePath "D:\PROJETOVM\Samples\suspeito.exe" -TimeoutSeconds 120 -ReportTransport Serial
```

Se o PowerShell Direct falhar de forma persistente, copie a amostra com o `04` até ao passo de cópia ou use `Copy-VMFile` manualmente; **dentro da VM** pode executar:

```powershell
cd C:\analysis_work
.\Run-MalwareAnalysis.ps1 -SamplePath "C:\analysis_work\suspeito.exe" -TimeoutSeconds 120 -HostRunId "<mesmo RunId do host>" -SerialReport:$true
```

O `04` continua a aceitar ficheiros em `C:\analysis.txt` via **Copy-VMFile** quando o transporte inclui Guest Service ou como retorno se o serial falhar.

## Conteúdo do relatório

- **Alterações em ficheiros:** criação, modificação e remoção nas pastas monitorizadas (`C:\Users\Public`, `C:\Windows\Temp`, `C:\ProgramData`, `C:\analysis_work`, `C:\Users\*\AppData\Local\Temp`, `C:\Users\*\AppData\Roaming`).
- **Registry:** alterações em Run, RunOnce, RunServices, Services, Image File Execution Options, StartupApproved.
- **Processos:** processos criados durante a análise (nome, PID, caminho).
- **Rede:** diferenças nas conexões TCP (Listen/Established) em relação ao baseline.
- **Serviços:** novos serviços em execução.
- **Tarefas agendadas:** novas tarefas agendadas (Task Scheduler).
- **Nota:** para chamadas API e rede em detalhe, recomenda-se **Sysmon** na VM e análise dos eventos (EID 3, 10, 22, etc.); o relatório base não inclui hooking de APIs.

## Configuração

Todas as variáveis (pasta base, nome da VM, snapshot, **ReportTransport** por defeito, limite de tamanho por ficheiro no serial) estão em **`_Config.ps1`**. A pasta base é **`D:\PROJETOVM`**. Para usar outra pasta, edite `$script:PROJETOVM_BasePath` em `_Config.ps1`.

## Segurança

- VM com rede **Internal**: sem acesso à internet.
- Snapshot limpo antes/depois de cada análise.
- Comunicação host↔VM: **Guest Service** (`Copy-VMFile`, activado só durante `04-Run-Sample.ps1`; desactivado ao terminar) e, opcionalmente, **COM1** para relatórios (Named Pipe; só **Gen1**).
- Evitar: partilhas de pastas, clipboard, drag-and-drop, bridge para a internet.

## Integração com o backend (opcional)

O driver `backend/vm_drivers/hyperv.py` pode **lançar** `04-Run-Sample.ps1` com o caminho da amostra e **ler os ficheiros** em `D:\PROJETOVM\Reports\`.

