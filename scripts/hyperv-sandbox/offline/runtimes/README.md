# Instaladores offline (runtimes)

Coloque aqui instaladores **offline** para que `05-FirstTimeVmSetup.ps1` os copie para a VM e instale (silenciosamente) **antes** de criar o snapshot `CleanState`.

## Ficheiros esperados (nomes)

- `VC_redist.x86.exe`
- `VC_redist.x64.exe`
- `ndp48-x86-x64-allos-enu.exe` (opcional, .NET Framework 4.8 offline)
- `windowsdesktop-runtime-8.0.*-win-x86.exe`
- `windowsdesktop-runtime-8.0.*-win-x64.exe`

> Nota: para o .NET Desktop Runtime 8, o script aceita **qualquer patch** `8.0.xx` (wildcard).

## Resultado esperado

Depois de correr `05-FirstTimeVmSetup.ps1`, o snapshot `CleanState` já deverá ter:

- VC++ Redistributables instalados
- .NET Desktop Runtime instalado

Assim, samples .NET e muitos binários nativos deixam de falhar com erros do tipo DLL/runtime em falta.

