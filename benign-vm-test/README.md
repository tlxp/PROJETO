# Benign VM Test

Programa **inofensivo** (.NET 8) para validar o pipeline da sandbox **sem malware real**. Reproduz, de forma controlada e reversível, comportamentos que a monitorização do **Caminho B** deve detetar.

Índice: [`docs/README.md`](../docs/README.md#análise-dinâmica--qual-caminho-usar) · pipeline: [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md).

> **Caminho B** (recomendado): validação completa via WPF ou `04-Run-Sample.ps1`.
> **Caminho A** (vm-agent): apenas smoke test de execução (`exitCode`/`stdout`) - **sem** telemetria de disco/registry.

## O que o programa faz

| Sinal | Ação na VM | Caminho B deve detetar |
|-------|-------------|------------------------|
| **Ficheiros** | Cria `C:\analysis_work\` e escreve `benign_test_marker.txt`, `child_process.txt`, `registry_flag.txt` | Alterações em ficheiros |
| **Registry** | `HKCU\Software\RATAnalyzerTest` (DWORD + strings) | Alterações no registry |
| **Persistência** | Entrada `RunOnce` em `HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce` | Persistência / Run keys |
| **Processo filho** | Arranca `cmd.exe` que escreve `child_process.txt` | Processos filhos |

O programa **não** contém lógica maliciosa. O snapshot `CleanState` repõe a VM após cada análise.

## Compilar e publicar

```powershell
cd benign-vm-test
dotnet publish -c Release
# Output: bin\Release\net8.0-windows\win-x64\publish\BenignVmTest.exe
```

Requisitos: **.NET 8 SDK**, target `net8.0-windows`.

## Utilização (Caminho B)

### Pré-requisitos

- Sandbox Hyper-V configurado (`01-Setup-MalwareSandbox.ps1`, `05-FirstTimeVmSetup.ps1`, snapshot `CleanState`).
- PowerShell **como Administrador** no host.
- `PROJETOVM_GuestPassword` definida - ver [`docs/production-secrets.md`](../docs/production-secrets.md).

### Passos

1. Copie `BenignVmTest.exe` para `D:\PROJETOVM\Samples\` (ou passe o caminho completo no parâmetro).
2. Execute no host:

```powershell
cd "<RAIZ-DO-REPO>\scripts\hyperv-sandbox"
.\04-Run-Sample.ps1 -SamplePath "D:\PROJETOVM\Samples\BenignVmTest.exe" -TimeoutSeconds 120
```

3. Abra o relatório em `D:\PROJETOVM\Reports\analysis_<RunId>.txt`.

### O que confirmar no relatório

Procure seções semelhantes a:

- **Ficheiros** - criação/alteração em `C:\analysis_work\` (`benign_test_marker.txt`, `child_process.txt`, `registry_flag.txt`).
- **Registry** - chave `HKCU\Software\RATAnalyzerTest` e/ou `RunOnce\RATAnalyzerBenignFlag`.
- **Processos** - `cmd.exe` como filho de `BenignVmTest.exe`.

Se estas entradas aparecerem, o pipeline de telemetria comportamental está funcional.

## Utilização (Caminho A - smoke test)

1. Publique o vm-agent na VM e configure o backend (`SANDBOX_VM_DRIVER=hyperv`, `VM_AGENT_TOKEN`, …) - ver [`vm-agent/README.md`](../vm-agent/README.md).
2. Envie `BenignVmTest.exe` via análise **dinâmica** na webapp ou `POST /api/analysis?analysis_type=dynamic`.
3. No `dynamicReport`, confirme `exitCode: 0` e linhas `[benign-vm-test]` em `stdout`.

> No Caminho A **não** espere listas de `fileSystem`/`registry` preenchidas - o vm-agent ainda devolve `monitoring: "not_implemented"`.

## Saída esperada (consola)

```
[benign-vm-test] início
[benign-vm-test] ficheiro escrito: C:\analysis_work\benign_test_marker.txt
[benign-vm-test] registry escrito: HKCU\Software\RATAnalyzerTest
[benign-vm-test] RunOnce escrito: HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce\RATAnalyzerBenignFlag
[benign-vm-test] ficheiro-flag escrito: C:\analysis_work\registry_flag.txt
[benign-vm-test] processo filho concluído: C:\analysis_work\child_process.txt
[benign-vm-test] fim
```

## Resolução de problemas

| Sintoma | Ação |
|---------|-------|
| Relatório vazio ou timeout | [`TROUBLESHOOTING.md`](../scripts/hyperv-sandbox/TROUBLESHOOTING.md) - credenciais guest, PsDirect, verificação SHA256 |
| Amostra falha na VM (exit ≠ 0) | Runtimes em falta - [`offline/runtimes/README.md`](../scripts/hyperv-sandbox/offline/runtimes/README.md), `07-Ensure-Runtimes.ps1` |
| Sem entradas de registry/ficheiros | Confirme que está no **Caminho B**, não no vm-agent |
| VM em estado sujo | `00-Reset-Sandbox.ps1` ou restore manual do snapshot `CleanState` |

## Estrutura

```
benign-vm-test/
├── Program.cs                  # Entrada — delega em BenignVmTestRunner
├── BenignVmTestPaths.cs        # Caminhos/registry esperados no relatório (testável)
├── BenignVmTestRunner.cs       # Lógica inofensiva (ficheiro, registry, processo filho)
├── BenignVmTest.csproj
├── BenignVmTest.Tests/         # xUnit — paths + smoke de stdout (Windows)
└── README.md
```

Parte da solução `RatAnalyzer.sln`. CI: `dotnet test RatAnalyzer.sln -c Release`.
