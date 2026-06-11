# Execução da análise dentro da VM.
# Carregado via dot-sourcing (mesmo scope).
#
# A análise é lançada de forma DESTACADA (Launch-AnalysisDetached.ps1): um processo
# powershell.exe separado dentro da VM corre Run-MalwareAnalysis.ps1 e o host devolve
# logo o controlo. Assim a análise sobrevive ao fecho da sessão PowerShell Direct
# (VMBus) e o relatório chega ao host por COM1 -> Named Pipe, mesmo que o PS Direct
# caia a meio ("The Hyper-V socket target process has ended.").

function Start-DetachedAnalysisInVm {
    param(
        [string] $VM,
        [pscredential] $Cred,
        [string] $VmSamplePath,
        [int] $TimeoutSec,
        [string] $VmScriptDir,
        [string] $SampleSha256,
        [string] $HostRunId = ""
    )

    $vmConfigPath   = Join-Path $VmScriptDir "launch_params.json"
    $vmLauncherPath = Join-Path $VmScriptDir "Launch-AnalysisDetached.ps1"
    $vmAnalysisPath = Join-Path $VmScriptDir "Run-MalwareAnalysis.ps1"

    $launchConfig = [ordered]@{
        AnalysisScriptPath = $vmAnalysisPath
        WorkingDirectory   = $VmScriptDir
        SamplePath         = $VmSamplePath
        TimeoutSeconds     = $TimeoutSec
        SampleHash         = $SampleSha256
        ExecutionMode      = "auto"
        SampleArguments    = ""
        DllExport          = ""
        RequireSysmon      = $false
        CaptureWpr         = $false
        HostRunId          = $HostRunId
    }
    $launchJson = $launchConfig | ConvertTo-Json -Compress

    # Escrever launch_params.json dentro da VM (evita scriptblocks remotos grandes).
    Invoke-Command -VMName $VM -Credential $Cred -ScriptBlock {
        param($Path, $Json)
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $Path -Value $Json -Encoding UTF8
    } -ArgumentList $vmConfigPath, $launchJson -ErrorAction Stop | Out-Null

    # Lançar a análise destacada. Retorna depressa (o launcher só estabiliza o
    # processo filho ~1s e devolve JSON com o PID destacado).
    $launchOut = Invoke-Command -VMName $VM -Credential $Cred -ScriptBlock {
        param($LauncherPath, $ConfigPath)
        if (-not (Test-Path -LiteralPath $LauncherPath)) {
            throw "Launcher de análise não encontrado na VM: $LauncherPath"
        }
        & $LauncherPath -ConfigPath $ConfigPath
    } -ArgumentList $vmLauncherPath, $vmConfigPath -ErrorAction Stop

    foreach ($l in @($launchOut)) {
        if ($null -eq $l) { continue }
        $s = ($l | Out-String).Trim()
        if (-not $s) { continue }
        Write-LogHost ("      [LAUNCH] {0}" -f $s)
    }

    return $launchOut
}
