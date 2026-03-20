# Sandbox Hyper-V com relatório via porta serial (Named Pipe)

Ambiente isolado para análise comportamental de malware: VM Hyper-V sem internet, snapshot limpo, e **exfiltração do relatório via porta serial virtual** (Named Pipe), sem usar rede nem partilhas.

- **Pasta base:** `D:\PROJETOVM` (VM, Reports, Samples, Logs).
- **Fluxo:** criar VM → colocar .exe/.dll → executar na VM → monitorizar alterações (ficheiros, registry, processos, rede, serviços, tarefas) → relatório em terceira pessoa → restaurar snapshot → encerrar VM → relatório guardado no host.

## Pré-requisitos

- Windows 10/11 Pro ou Enterprise (ou Server) com **Hyper-V**.
- PowerShell **como Administrador** para setup e orquestração.
- VM com Windows instalado e **porta COM1** configurada para o Named Pipe no host.

## Estrutura de ficheiros

```
scripts/hyperv-sandbox/
├── _Config.ps1                  # Configuração central (D:\PROJETOVM, nomes VM/pipe/snapshot)
├── 01-Setup-MalwareSandbox.ps1  # Setup único: pastas, VM, switch, IP host, snapshot, COM1→Pipe
├── 02-Host-ReceiveReport.ps1    # Host: recebe relatório no pipe, grava em D:\PROJETOVM\Reports
├── 03-Install-SysmonInGuest.ps1 # Host: instala Sysmon dentro da VM (após Windows instalado)
├── 04-Run-Sample.ps1            # Host: orquestração (restore, start, copy, run, receive, restore)
├── 05-FirstTimeVmSetup.ps1      # Host: primeira entrada — instala software (winget) na VM e cria snapshot
├── vm/
│   ├── Prepare-RealisticEnvironment.ps1  # VM: hostname, user, serviços, BIOS, winget (opcional)
│   ├── Run-MalwareAnalysis.ps1   # VM: baseline → executa sample → diff → relatório → COM1
│   └── Send-ReportViaCom.ps1    # VM: envia C:\analysis.txt via COM1
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
   - O script cria `D:\PROJETOVM`, a VM `MalwareSandbox`, o switch interno `SandboxSwitch`, atribui 192.168.100.1/24 ao adaptador do host (se existir), configura COM1→Named Pipe e cria o snapshot `CleanState` (se a VM estiver desligada).
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
7. Copie para a VM os scripts da pasta `vm\` (ex.: para `C:\analysis_work\`):
   - `Run-MalwareAnalysis.ps1`
   - `Send-ReportViaCom.ps1`
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

O relatório será guardado em `D:\PROJETOVM\Reports\analysis_<timestamp>.txt`.

Se `Invoke-Command -VMName` não funcionar (ex.: versões diferentes de Windows), use:

```powershell
.\04-Run-Sample.ps1 -SamplePath "D:\PROJETOVM\Samples\suspeito.exe" -NoInvokeCommand
```

Neste caso, o script copia a amostra e fica à espera do relatório; **dentro da VM** execute manualmente:

```powershell
cd C:\analysis_work
.\Run-MalwareAnalysis.ps1 -SamplePath "C:\analysis_work\suspeito.exe" -TimeoutSeconds 120
```

### Receber apenas o relatório (manual)

Se quiser correr o listener do pipe à parte:

```powershell
.\02-Host-ReceiveReport.ps1 -OutputPath "D:\PROJETOVM\Reports\meu_relatorio.txt"
```

Na VM, após a análise, o envio é feito por `Send-ReportViaCom.ps1` (chamado automaticamente por `Run-MalwareAnalysis.ps1`).

## Conteúdo do relatório

- **Alterações em ficheiros:** criação, modificação e remoção nas pastas monitorizadas (`C:\Users\Public`, `C:\Windows\Temp`, `C:\ProgramData`, `C:\analysis_work`, `C:\Users\*\AppData\Local\Temp`, `C:\Users\*\AppData\Roaming`).
- **Registry:** alterações em Run, RunOnce, RunServices, Services, Image File Execution Options, StartupApproved.
- **Processos:** processos criados durante a análise (nome, PID, caminho).
- **Rede:** diferenças nas conexões TCP (Listen/Established) em relação ao baseline.
- **Serviços:** novos serviços em execução.
- **Tarefas agendadas:** novas tarefas agendadas (Task Scheduler).
- **Nota:** para chamadas API e rede em detalhe, recomenda-se **Sysmon** na VM e análise dos eventos (EID 3, 10, 22, etc.); o relatório base não inclui hooking de APIs.

## Configuração

Todas as variáveis (pasta base, nome da VM, snapshot, pipe) estão em **`_Config.ps1`**. A pasta base é **`D:\PROJETOVM`**. Para usar outra pasta, edite `$script:PROJETOVM_BasePath` em `_Config.ps1`.

## Segurança

- VM com rede **Internal**: sem acesso à internet.
- Snapshot limpo antes/depois de cada análise.
- Comunicação host↔VM: **Copy-VMFile** (Guest Service ativado apenas durante a orquestração) e **Named Pipe** para o relatório (unidirecional VM→host).
- Evitar: partilhas de pastas, clipboard, drag-and-drop, bridge para a internet.

## Integração com o backend (opcional)

O driver `backend/vm_drivers/hyperv.py` usa atualmente o **VM Agent HTTP** (upload/run/report). Para usar **apenas** o fluxo com serial/pipe, pode:

- Correr `04-Run-Sample.ps1` a partir do backend (por exemplo via `subprocess` ou agendamento) com o `SamplePath` do job e ler o relatório em `D:\PROJETOVM\Reports\`.
- Ou implementar um driver alternativo (ex.: `hyperv_serial`) que execute estes scripts e leia o ficheiro de relatório gerado.
