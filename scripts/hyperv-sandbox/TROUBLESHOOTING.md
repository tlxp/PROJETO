# Resolução de problemas - Sandbox Hyper-V (Caminho B)

FAQ geral: [`docs/faq.md`](../../docs/faq.md) · índice: [`docs/README.md`](../../docs/README.md).

**Pré-requisitos:** PowerShell como Administrador · VM `MalwareSandbox` + snapshot `CleanState` · `PROJETOVM_GuestPassword` · logs em `D:\PROJETOVM\Logs\Runs\<RunId>\`.

| Sintoma | Ação |
|---------|-------|
| `Assert-SandboxVmNetworkIsolation` falha | VM só com adaptador no switch Internal `SandboxSwitch` |
| Credenciais guest falham | `PROJETOVM_GuestUser` / `PROJETOVM_GuestPassword` |
| Timeout no relatório | Ver fallback Copy-VMFile; [`SERIAL_REPORT_PROTOCOL.md`](SERIAL_REPORT_PROTOCOL.md) |
| VM não arranca | Espaço em disco; restaurar `CleanState` |
| Amostra falha na VM | Runtimes: [`offline/runtimes/`](offline/runtimes/README.md) |
| Run anterior incompleto | `00-Reset-Sandbox.ps1` ou stop + restore snapshot |

**Validação sem malware:** [`benign-vm-test`](../../benign-vm-test/README.md) → `04-Run-Sample.ps1 -SamplePath ...\BenignVmTest.exe`

Pipeline: [`README.md`](README.md).
