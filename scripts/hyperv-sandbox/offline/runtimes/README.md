# Instaladores offline (runtimes)

Coloque aqui instaladores **offline** para que `05-FirstTimeVmSetup.ps1` os copie para a VM guest e
instale silenciosamente **antes** de criar o snapshot `CleanState`.

Sem estes pacotes, amostras .NET e binários nativos podem falhar na VM com erros de runtime/DLL em falta.

## Ficheiros esperados

| Ficheiro | Pacote |
|----------|--------|
| `VC_redist.x86.exe` | Visual C++ Redistributable (x86) |
| `VC_redist.x64.exe` | Visual C++ Redistributable (x64) |
| `ndp48-x86-x64-allos-enu.exe` | .NET Framework 4.8 offline *(opcional)* |
| `windowsdesktop-runtime-8.0.*-win-x86.exe` | .NET Desktop Runtime 8 (x86) |
| `windowsdesktop-runtime-8.0.*-win-x64.exe` | .NET Desktop Runtime 8 (x64) |

> Para o .NET Desktop Runtime 8, o script aceita **qualquer patch** `8.0.xx` (wildcard no nome).

## Resultado esperado

Após `05-FirstTimeVmSetup.ps1`, o snapshot `CleanState` deve incluir:

- VC++ Redistributables (x86 e x64)
- .NET Desktop Runtime 8 (x86 e x64, conforme os instaladores fornecidos)

Documentação do pipeline: [`../../README.md`](../../README.md).
