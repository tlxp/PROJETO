<#
.SYNOPSIS
    Instala Sysmon dentro da VM MalwareSandbox e prepara-a para captura de eventos.
.DESCRIPTION
    A correr NO HOST, depois do Windows já estar instalado na VM.

    Fluxo:
      - Garante que a VM existe.
      - Arranca a VM e espera pelo boot.
      - Ativa temporariamente o Guest Service Interface.
      - Copia Sysmon e o ficheiro de configuração para C:\tools\sysmon na VM.
      - Executa Sysmon com -accepteula -i <config> dentro da VM.

    Após este passo, recomenda-se desligar a VM e atualizar o snapshot limpo
    (CleanState) para que futuras análises usem sempre uma imagem com Sysmon ativo.

.PARAMETER SysmonExePath
    Caminho, NO HOST, para o binário Sysmon 64-bit (ex.: D:\Tools\Sysmon\Sysmon64.exe).

.PARAMETER SysmonConfigPath
    Caminho, NO HOST, para o ficheiro de configuração XML do Sysmon.

.PARAMETER BootWaitSeconds
    Tempo de espera após arrancar a VM para garantir que o Windows está pronto.

.EXAMPLE
    .\03-Install-SysmonInGuest.ps1
#>
#Requires -RunAsAdministrator

param(
    # Se omitido, o script tenta detetar automaticamente e/ou descarregar Sysmon.
    [string] $SysmonExePath = "",

    # Se omitido, o script tenta detetar automaticamente e/ou obter uma config default.
    [string] $SysmonConfigPath = "",

    [int] $BootWaitSeconds = 60
)

$ErrorActionPreference = "Stop"

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName = $script:PROJETOVM_VMName
$GuestUser = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword


# Funções auxiliares (host)
# Extraídas para .\InstallSysmon\ e carregadas via dot-sourcing (mesmo scope).
$InstallSysmonLibDir = Join-Path $PSScriptRoot 'InstallSysmon'
. (Join-Path $InstallSysmonLibDir 'SysmonResolve.ps1')
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    throw "VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1 e instale o Windows na VM."
}

$SysmonExePath = Resolve-SysmonExePath -PreferredPath $SysmonExePath
$SysmonConfigPath = Resolve-SysmonConfigPath -PreferredPath $SysmonConfigPath -SysmonExeResolved $SysmonExePath

Write-Host "=== Instalação do Sysmon na VM '$VMName' ==="
Write-Host "Binário Sysmon (host): $SysmonExePath"
Write-Host "Configuração (host):   $SysmonConfigPath"
Write-Host ""

$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# 1) Ligar VM (se ainda não estiver ligada)
if ($vm.State -ne "Running") {
    Write-Host "[1/5] A arrancar a VM..."
    $psOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds 0
    if ($psOk -is [pscredential]) { $cred = $psOk }
} else {
    Write-Host "[1/5] VM já se encontra ligada."
}

Write-Host "      A aguardar PowerShell Direct (verificação a cada 10s, sem timeout)..."
$psOk2 = Wait-VMPowerShellDirectReady -VMName $VMName -CredentialCandidates $credCandidates -TimeoutSeconds 0 -LogPath $null -LogIntervalSeconds 10
if ($psOk2 -is [pscredential]) { $cred = $psOk2 }

# 2) Ativar Guest Service Interface para Copy-VMFile / Invoke-Command
#    (O 04 também reconfigura COM1→pipe após cada restore de snapshot, incluindo snapshot atualizado pelo Sysmon.)
Write-Host "[2/5] A ativar Guest Service Interface na VM..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 5

# 3) Copiar Sysmon e configuração para a VM
Write-Host "[3/5] A copiar Sysmon para a VM..."
$guestSysmonDir   = "C:\tools\sysmon"
$guestSysmonExe   = Join-Path $guestSysmonDir "Sysmon64.exe"
$guestSysmonConfig = Join-Path $guestSysmonDir "sysmon-config.xml"

Copy-SandboxVMFile -VMName $VMName -SourcePath $SysmonExePath -DestinationPath $guestSysmonExe
Copy-SandboxVMFile -VMName $VMName -SourcePath $SysmonConfigPath -DestinationPath $guestSysmonConfig
Write-Host "      Sysmon e configuração copiados para $guestSysmonDir."

# 4) Instalar Sysmon dentro da VM
Write-Host "[4/5] A instalar Sysmon dentro da VM..."
try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($exePath, $configPath)
        if (-not (Test-Path $exePath)) {
            throw "Sysmon não encontrado dentro da VM em: $exePath"
        }
        if (-not (Test-Path $configPath)) {
            throw "Configuração Sysmon não encontrada dentro da VM em: $configPath"
        }

        Write-Host "    [VM] A instalar Sysmon com configuração: $configPath"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.Arguments = "-accepteula -i `"$configPath`""
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $null = $proc.WaitForExit(600000)  # até 10 minutos
        Write-Host "    [VM] Sysmon terminou com ExitCode $($proc.ExitCode)."

        # Validar imediatamente (serviço + canal de eventos)
        $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
        if (-not $svc) { $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue }

        if (-not $svc) {
            throw "Sysmon aparenta ter sido instalado mas o serviço Sysmon64/Sysmon não existe."
        }

        if ($svc.Status -ne "Running") {
            try {
                Start-Service -Name $svc.Name -ErrorAction Stop
                Start-Sleep -Milliseconds 500
                $svc = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            } catch { }
        }

        $logName = "Microsoft-Windows-Sysmon/Operational"
        $logPresent = $false
        try { $logPresent = [bool](Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue) } catch { $logPresent = $false }

        # Mostrar a config ativa (best-effort). `sysmon -c` costuma funcionar sem UI.
        try {
            $psiC = New-Object System.Diagnostics.ProcessStartInfo
            $psiC.FileName = $exePath
            $psiC.Arguments = "-c"
            $psiC.UseShellExecute = $false
            $psiC.RedirectStandardOutput = $true
            $psiC.RedirectStandardError = $true
            $psiC.CreateNoWindow = $true
            $p2 = New-Object System.Diagnostics.Process
            $p2.StartInfo = $psiC
            $null = $p2.Start()
            $out = $p2.StandardOutput.ReadToEnd()
            $err = $p2.StandardError.ReadToEnd()
            $null = $p2.WaitForExit(120000)
            if ($out) { Write-Host ("    [VM] sysmon -c: " + ($out -replace "`r","").Trim()) }
            if ($err) { Write-Host ("    [VM] sysmon -c (stderr): " + ($err -replace "`r","").Trim()) }
        } catch { }

        Write-Host ("    [VM] Serviço: {0} | Estado: {1} | Canal Sysmon: {2}" -f $svc.Name, $svc.Status, $logPresent)
        if ($svc.Status -ne "Running" -or -not $logPresent) {
            throw ("Sysmon não ficou operacional. svc_status={0} log_present={1}" -f $svc.Status, $logPresent)
        }
    } -ArgumentList $guestSysmonExe, $guestSysmonConfig -ErrorAction Stop
}
catch {
    Write-Warning "Falha ao instalar Sysmon dentro da VM: $_"
    Write-Warning "Verifique se a versão do Windows na VM suporta PowerShell Direct / Invoke-Command."
    throw
}

Write-Host "[5/5] Sysmon instalado na VM (serviço Sysmon deve estar ativo)."
Write-Host ""
Write-Host "Recomendação:"
Write-Host "  1. Desligue a VM para capturar um novo snapshot limpo com Sysmon:"
Write-Host "       Stop-VM -Name $VMName -Force"
Write-Host "  2. Crie/atualize o snapshot CleanState (ou o nome definido em _Config.ps1):"
Write-Host "       Checkpoint-VM -Name $VMName -SnapshotName $($script:PROJETOVM_SnapshotName)"
Write-Host ""
Write-Host "Após este passo, as próximas análises comportamentais já terão Sysmon ativo na imagem base."

