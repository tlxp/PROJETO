# --- Módulo: Launch-AnalysisDetached.ps1 ---
# --- Launcher destacado para Run-MalwareAnalysis.ps1 ---
<#
.SYNOPSIS
    Lança Run-MalwareAnalysis.ps1 num processo PowerShell separado (guest).
.DESCRIPTION
    Usa cmd.exe "start /B" para criar um processo independente da sessão PowerShell Direct.
    Só reporta ok=true quando guest_alive.txt aparece (Run-MalwareAnalysis arrancou de facto).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $ConfigPath = "C:\analysis_work\launch_params.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Leitura de propriedades do JSON de arranque ---
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

# --- Gravação do estado de arranque em ficheiro JSON ---
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

# --- Escape seguro de argumentos para cmd.exe ---
function Format-CmdArgument {
    param([string] $Value)
    if ($null -eq $Value) { return '""' }
    $s = [string]$Value
    if ($s.Length -eq 0) { return '""' }
    if ($s -match '[\s"&|^<>()]') {
        return '"' + ($s -replace '"', '""') + '"'
    }
    return $s
}

# --- Espera pelo ficheiro guest_alive.txt (prova de arranque) ---
function Wait-ForGuestAliveFile {
    param(
        [Parameter(Mandatory = $true)][string] $AlivePath,
        [int] $TimeoutSeconds = 25
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $AlivePath) {
            try {
                $line = Get-Content -LiteralPath $AlivePath -TotalCount 1 -ErrorAction Stop
                if ($line -match 'pid=(\d+)') {
                    return [int]$Matches[1]
                }
                return $PID
            } catch {
                return $PID
            }
        }
        Start-Sleep -Milliseconds 400
    }
    return 0
}

# --- Fluxo principal de arranque desacoplado ---
$workDir = "C:\analysis_work"
try {
    # Carrega e valida launch_params.json
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
    if (-not (Test-Path -LiteralPath $workDir)) {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }

    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $psExe)) {
        $psExe = "powershell.exe"
    }

    # Compatibilidade com launch_params.json antigos (WaitForSampleExit)
    $timeoutKill = Get-LaunchConfigBool -Config $cfg -Name "SampleTimeoutKill"
    if (-not $timeoutKill) {
        $waitExitVal = Get-LaunchConfigProperty -Config $cfg -Name "WaitForSampleExit"
        if ($null -ne $waitExitVal) { $timeoutKill = -not [bool]$waitExitVal }
    }

    # Monta a linha de comandos para Run-MalwareAnalysis.ps1
    $psArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptFile,
        "-SamplePath", (Get-LaunchConfigString -Config $cfg -Name "SamplePath"),
        "-TimeoutSeconds", (Get-LaunchConfigString -Config $cfg -Name "TimeoutSeconds"),
        "-SampleHash", (Get-LaunchConfigString -Config $cfg -Name "SampleHash"),
        "-ExecutionMode", (Get-LaunchConfigString -Config $cfg -Name "ExecutionMode"),
        "-WorkingDirectory", [string]$workDir
    )
    if ($timeoutKill) { $psArgs += "-SampleTimeoutKill" }

    $sampleArgsVal = Get-LaunchConfigString -Config $cfg -Name "SampleArguments"
    if ($sampleArgsVal.Length -gt 0) {
        $psArgs += @("-SampleArguments", $sampleArgsVal)
    }

    $dllVal = Get-LaunchConfigString -Config $cfg -Name "DllExport"
    if ($dllVal.Length -gt 0) {
        $psArgs += @("-DllExport", $dllVal)
    }

    if (Get-LaunchConfigBool -Config $cfg -Name "RequireSysmon") { $psArgs += "-RequireSysmon" }
    if (Get-LaunchConfigBool -Config $cfg -Name "CaptureWpr") { $psArgs += "-CaptureWpr" }
    $hostRunIdVal = Get-LaunchConfigString -Config $cfg -Name "HostRunId"
    if ($hostRunIdVal.Length -gt 0) {
        $psArgs += @("-HostRunId", $hostRunIdVal)
    }

    foreach ($ai in 0..($psArgs.Count - 1)) {
        if ($null -eq $psArgs[$ai]) { throw "ArgumentList contém entrada nula na posição $ai." }
        if (([string]$psArgs[$ai]).Length -eq 0) { throw "ArgumentList contém entrada vazia na posição $ai." }
    }

    $launchLog = Join-Path $workDir "analysis_launch.log"
    $alivePath = Join-Path $workDir "guest_alive.txt"

    # Limpa artefatos de arranques anteriores
    try { if (Test-Path -LiteralPath $alivePath) { Remove-Item -LiteralPath $alivePath -Force -ErrorAction SilentlyContinue } } catch { }
    try { if (Test-Path -LiteralPath $launchLog) { Remove-Item -LiteralPath $launchLog -Force -ErrorAction SilentlyContinue } } catch { }

    Set-Content -LiteralPath (Join-Path $workDir "launch_cmdline.txt") -Value @(
        "ps=$psExe $($psArgs -join ' ')"
        "started_at=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')"
    ) -Encoding UTF8

    # Start-Process evita quoting frágil de cmd.exe start /B
    $proc = Start-Process -FilePath $psExe -ArgumentList $psArgs -WorkingDirectory $workDir `
        -WindowStyle Hidden -PassThru

    # Só considera sucesso quando guest_alive.txt confirma o PID
    $detachedPid = Wait-ForGuestAliveFile -AlivePath $alivePath -TimeoutSeconds 25
    if ($detachedPid -le 0) {
        $tail = ""
        if (Test-Path -LiteralPath $launchLog) {
            $tail = (Get-Content -LiteralPath $launchLog -Tail 5 -ErrorAction SilentlyContinue) -join ' | '
        }
        throw "Run-MalwareAnalysis não arrancou (sem guest_alive.txt em 25s). Log: $tail"
    }

    $stillRunning = $null -ne (Get-Process -Id $detachedPid -ErrorAction SilentlyContinue)
    if (-not $stillRunning) {
        throw "Processo de análise (pid=$detachedPid) terminou logo após guest_alive.txt"
    }

    $launchInfo = @{
        ok = $true
        detached_pid = $detachedPid
        analysis_script = $scriptFile
        launcher = $PSCommandPath
        config = $ConfigPath
        launched_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
        launch_method = "start_process"
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
