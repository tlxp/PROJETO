<#
.SYNOPSIS
    Lança Run-MalwareAnalysis.ps1 num processo PowerShell separado (guest).
.DESCRIPTION
    O host copia launch_params.json e invoca este script via PowerShell Direct com
    Start-Process, para evitar scriptblocks remotos grandes e instáveis.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $ConfigPath = "C:\analysis_work\launch_params.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-LaunchConfigProperty {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)][string] $Name
    )

    foreach ($prop in $Config.PSObject.Properties) {
        if ($prop.Name -eq $Name) { return $prop.Value }
    }
    return $null
}

function Get-LaunchConfigString {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $value = Get-LaunchConfigProperty -Config $Config -Name $Name
    if ($null -eq $value) { return "" }
    return [string]$value
}

function Get-LaunchConfigBool {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $value = Get-LaunchConfigProperty -Config $Config -Name $Name
    if ($null -eq $value) { return $false }
    return [bool]$value
}

function Write-LaunchStatusFile {
    param(
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [Parameter(Mandatory = $true)][hashtable] $Payload
    )

    if ([string]::IsNullOrWhiteSpace($WorkDir)) { return }
    try {
        if (-not (Test-Path -LiteralPath $WorkDir)) {
            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
        }
        $path = Join-Path $WorkDir "launch_status.json"
        $Payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $path -Encoding UTF8
    } catch { }
}

$workDir = "C:\analysis_work"
try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Ficheiro de configuração não encontrado: $ConfigPath"
    }

    $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if (-not $cfg) { throw "Configuração de arranque inválida em: $ConfigPath" }

    $scriptFile = Get-LaunchConfigString -Config $cfg -Name "AnalysisScriptPath"
    if ([string]::IsNullOrWhiteSpace($scriptFile)) {
        throw "AnalysisScriptPath em falta em: $ConfigPath"
    }
    if (-not (Test-Path -LiteralPath $scriptFile)) {
        throw "Não encontrei o script de análise na VM: $scriptFile"
    }

    $workDir = Get-LaunchConfigString -Config $cfg -Name "WorkingDirectory"
    if ([string]::IsNullOrWhiteSpace($workDir)) {
        $workDir = Split-Path -Parent $scriptFile
    }
    if ([string]::IsNullOrWhiteSpace($workDir)) { $workDir = "C:\analysis_work" }

    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $psExe)) {
        $psExe = "powershell.exe"
    }

    $argList = New-Object System.Collections.Generic.List[string]
    [void]$argList.Add("-NoProfile")
    [void]$argList.Add("-ExecutionPolicy"); [void]$argList.Add("Bypass")
    [void]$argList.Add("-File");            [void]$argList.Add($scriptFile)
    [void]$argList.Add("-SamplePath");     [void]$argList.Add((Get-LaunchConfigString -Config $cfg -Name "SamplePath"))
    [void]$argList.Add("-TimeoutSeconds"); [void]$argList.Add((Get-LaunchConfigString -Config $cfg -Name "TimeoutSeconds"))
    [void]$argList.Add("-SampleHash");    [void]$argList.Add((Get-LaunchConfigString -Config $cfg -Name "SampleHash"))
    [void]$argList.Add("-ExecutionMode"); [void]$argList.Add((Get-LaunchConfigString -Config $cfg -Name "ExecutionMode"))

    $sampleArgsVal = Get-LaunchConfigString -Config $cfg -Name "SampleArguments"
    if ($sampleArgsVal.Length -gt 0) {
        [void]$argList.Add("-SampleArguments")
        [void]$argList.Add($sampleArgsVal)
    }

    [void]$argList.Add("-WorkingDirectory"); [void]$argList.Add([string]$workDir)

    $dllVal = Get-LaunchConfigString -Config $cfg -Name "DllExport"
    if ($dllVal.Length -gt 0) {
        [void]$argList.Add("-DllExport")
        [void]$argList.Add($dllVal)
    }

    $requireSysmon = Get-LaunchConfigBool -Config $cfg -Name "RequireSysmon"
    $captureWpr = Get-LaunchConfigBool -Config $cfg -Name "CaptureWpr"

    if ($requireSysmon) { [void]$argList.Add("-RequireSysmon") }
    if ($captureWpr) { [void]$argList.Add("-CaptureWpr") }
    $hostRunIdVal = Get-LaunchConfigString -Config $cfg -Name "HostRunId"
    if ($hostRunIdVal.Length -gt 0) {
        [void]$argList.Add("-HostRunId")
        [void]$argList.Add($hostRunIdVal)
    }

    for ($ai = $argList.Count - 1; $ai -ge 0; $ai--) {
        if ($null -eq $argList[$ai]) { throw "Lista de ArgumentList contém entrada nula na posição $ai." }
        if (([string]$argList[$ai]).Length -eq 0) { throw "Lista de ArgumentList contém entrada vazia na posição $ai." }
    }

    $argArr = $argList.ToArray()
    if (-not $argArr -or $argArr.Length -eq 0) {
        throw "ArgumentList ficou vazia (unexpected)."
    }

    # NOTA: Usar ProcessStartInfo em vez de Start-Process -WindowStyle Hidden.
    # Sob PowerShell Direct (VMBus), nao ha sessao interactiva/window station,
    # por isso -WindowStyle Hidden pode lancar excepcao Win32 e matar o processo
    # PS Direct, causando "The Hyper-V socket target process has ended."
    # ProcessStartInfo com CreateNoWindow=$true nao toca na window station.
    $psi2 = New-Object System.Diagnostics.ProcessStartInfo
    $psi2.FileName         = $psExe
    # Reconstruir argList como string para ProcessStartInfo
    $argStr = ($argList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi2.Arguments        = $argStr
    $psi2.WorkingDirectory = $workDir
    $psi2.UseShellExecute  = $false
    $psi2.CreateNoWindow   = $true

    $p = [System.Diagnostics.Process]::Start($psi2)
    if (-not $p) { throw "Process.Start nao devolveu processo." }

    # Breve pausa para o processo filho estabilizar antes de fechar o pipe VMBus.
    Start-Sleep -Seconds 1

    $launchInfo = @{
        ok = $true
        detached_pid = $p.Id
        analysis_script = $scriptFile
        launcher = $PSCommandPath
        config = $ConfigPath
        launched_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    }
    Write-LaunchStatusFile -WorkDir $workDir -Payload $launchInfo
    $launchInfo | ConvertTo-Json -Compress
}
catch {
    $err = $_.Exception.Message
    Write-LaunchStatusFile -WorkDir $workDir -Payload @{
        ok = $false
        launcher = $PSCommandPath
        config = $ConfigPath
        failed_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
        error = $err
    }
    try {
        if (-not (Test-Path -LiteralPath $workDir)) {
            New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        }
        $errPath = Join-Path $workDir "launch_error.txt"
        @(
            "launcher=$PSCommandPath",
            "config=$ConfigPath",
            "failed_at=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')",
            "error=$err"
        ) | Set-Content -LiteralPath $errPath -Encoding UTF8
    } catch { }
    throw
}