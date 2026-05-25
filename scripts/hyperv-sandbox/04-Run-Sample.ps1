<#
.SYNOPSIS
    Orquestração no host: restaura VM, copia amostra, executa análise, recebe relatório via pipe, restaura snapshot.
.DESCRIPTION
    Fluxo: Restore snapshot -> Start VM -> (opcional) Guest Service para Copy-VMFile ->
    Copiar sample e scripts para VM -> Iniciar listener do pipe em background ->
    Executar análise na VM (Invoke-Command ou manual) -> Esperar relatório ->
    Stop VM -> Restore snapshot -> Relatório em D:\PROJETOVM\Reports\.
.PARAMETER SamplePath
    Caminho no HOST do ficheiro .exe ou .dll a analisar.
    Se omitido, o script escolhe automaticamente o ficheiro mais recente em D:\PROJETOVM\Samples\.
.PARAMETER TimeoutSeconds
    Tempo máximo de execução do sample dentro da VM.
.PARAMETER BootWaitSeconds
    Reservado (o arranque usa espera por PowerShell Direct com credenciais do _Config.ps1, sem sleep fixo).
#>
#Requires -RunAsAdministrator

param(
    [string]$SamplePath = "",
    [string]$RunId,
    [int]$TimeoutSeconds = 120,
    [int]$BootWaitSeconds = 60,
    [int]$GlobalTimeoutSeconds = 600
)

# Recarregar sempre o módulo (evita cache com versões antigas durante troubleshooting)
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$ErrorActionPreference = "Stop"

$analysisStart = Get-Date

# Carregar configuração (D:\PROJETOVM)
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
$BasePath = $script:PROJETOVM_BasePath
$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$PipeName = $script:PROJETOVM_PipeName
$ReportsDir = $script:PROJETOVM_ReportsPath
$VMScriptsPath = "C:\analysis_work"
$GuestUser = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

function Resolve-AutoSamplePath {
    param([string] $ProvidedPath, [string] $SamplesDir)

    function Ensure-DefaultSampleExists {
        param([string] $Dir)

        $defaultPath = Join-Path $Dir "sample_autogen.exe"
        if (Test-Path -LiteralPath $defaultPath) { return $defaultPath }

        try { New-Item -ItemType Directory -Path $Dir -Force | Out-Null } catch { }

        # Gerar um executável inofensivo (para permitir um "fluxo 100% automático")
        # Nota: usa Add-Type (csc) disponível no Windows.
        $src = @"
using System;
using System.IO;
using System.Threading;

public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            var work = @"C:\analysis_work";
            try { Directory.CreateDirectory(work); } catch { }
            var p = Path.Combine(work, "autogen_sample_ran.txt");
            File.WriteAllText(p, "ran at: " + DateTime.UtcNow.ToString("o"));
        }
        catch { }

        // Pequena pausa para existir "atividade" observável
        Thread.Sleep(1500);
        return 0;
    }
}
"@
        Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $defaultPath -OutputType ConsoleApplication -ErrorAction Stop | Out-Null
        return $defaultPath
    }

    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        if ([System.IO.File]::Exists($ProvidedPath)) { return [System.IO.Path]::GetFullPath($ProvidedPath) }
        Write-Error "Amostra não encontrada: $ProvidedPath"
        exit 1
    }

    if (-not (Test-Path -LiteralPath $SamplesDir)) {
        Write-Error "Pasta de samples não existe: $SamplesDir"
        exit 1
    }

    $candidate = Get-ChildItem -LiteralPath $SamplesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".exe", ".dll") } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        $auto = Ensure-DefaultSampleExists -Dir $SamplesDir
        if (-not (Test-Path -LiteralPath $auto)) {
            Write-Error "Nenhuma amostra encontrada e falhou ao criar sample automático em: $SamplesDir"
            exit 1
        }
        return $auto
    }
    return $candidate.FullName
}

$SamplePath = Resolve-AutoSamplePath -ProvidedPath $SamplePath -SamplesDir $script:PROJETOVM_SamplesPath

if (-not [System.IO.File]::Exists($SamplePath)) {
    Write-Error "Amostra não encontrada: $SamplePath"
    exit 1
}

function Get-PeMachineInfo {
    param([Parameter(Mandatory = $true)][string] $Path)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $br = New-Object System.IO.BinaryReader($fs)
            $mz = $br.ReadUInt16()
            if ($mz -ne 0x5A4D) { return @{ ok = $false; reason = "Não é um executável PE (sem header MZ)." } } # 'MZ'
            $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
            $peOff = $br.ReadUInt32()
            if ($peOff -lt 0 -or $peOff -gt ($fs.Length - 6)) { return @{ ok = $false; reason = "Header PE inválido (offset fora do ficheiro)." } }
            $fs.Seek([int64]$peOff, [System.IO.SeekOrigin]::Begin) | Out-Null
            $sig = $br.ReadUInt32()
            if ($sig -ne 0x00004550) { return @{ ok = $false; reason = "Não é um PE válido (assinatura PE\\0\\0 ausente)." } }
            $machine = $br.ReadUInt16()
            $machineName = switch ($machine) {
                0x014c { "x86" }
                0x8664 { "x64" }
                0x01c4 { "ARM" }
                0xAA64 { "ARM64" }
                default { ("0x{0:X4}" -f $machine) }
            }
            return @{ ok = $true; machine = $machine; machineName = $machineName }
        } finally {
            try { $fs.Dispose() } catch { }
        }
    } catch {
        return @{ ok = $false; reason = ("Falha ao ler header PE: " + $_.Exception.Message) }
    }
}

if ([System.IO.Path]::GetExtension($SamplePath).ToLowerInvariant() -ne ".exe") {
    Write-Error "Esta pipeline (Run-MalwareAnalysis) executa amostras como .exe. Ficheiro fornecido: $SamplePath"
    exit 1
}


function Test-ReportLooksComplete {
    param([string] $Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $txt = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($txt)) { return $false }
        # O relatório está completo quando contém o cabeçalho e o rodapé gerados por Run-MalwareAnalysis.ps1
        if ($txt -notmatch "RELAT") { return $false }
        if ($txt -notmatch "FIM DO RELAT") { return $false }
        return $true
    } catch {
        return $false
    }
}

$vmObj = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vmObj) {
    Write-Error "VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1"
    exit 1
}
$snap = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if (-not $snap) {
    Write-Error "Snapshot '$SnapshotName' não encontrado na VM '$VMName'. Crie-o após instalar o Windows na VM."
    exit 1
}

$sampleHash = Get-FileHash -LiteralPath $SamplePath -Algorithm SHA256
$sampleSha256 = $sampleHash.Hash

$sampleFileName = [System.IO.Path]::GetFileName($SamplePath)
$VMSamplePath = "C:\analysis_work\$sampleFileName"

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}
$ReportOutputPath = Join-Path $ReportsDir "analysis_$RunId.txt"

Ensure-DirectoryExists -Path $ReportsDir

# Logging básico do host
$LogsDir = $script:PROJETOVM_LogsPath
Ensure-DirectoryExists -Path $LogsDir
$RunsDir = Join-Path $LogsDir "Runs"
$RunDir = Join-Path $RunsDir $RunId
Ensure-DirectoryExists -Path $RunsDir
Ensure-DirectoryExists -Path $RunDir
$HostLogPath = Join-Path $RunDir "sandbox_run_$RunId.log"
$HostJsonPath = Join-Path $RunDir "run_$RunId.json"
function Add-LogLine { param([string]$Path, [string]$Value) Add-Content -Path $Path -Value "[$(Get-Date -Format 'HH:mm:ss')] $Value" }
Add-LogLine -Path $HostLogPath -Value "==== Sandbox Run $RunId ===="
Add-LogLine -Path $HostLogPath -Value "Sample: $SamplePath"
Add-LogLine -Path $HostLogPath -Value "Sample SHA256: $sampleSha256"
Add-LogLine -Path $HostLogPath -Value "VM: $VMName  Snapshot: $SnapshotName"
Add-LogLine -Path $HostLogPath -Value "Report: $ReportOutputPath"
Add-LogLine -Path $HostLogPath -Value "RunDir: $RunDir"
if ($vmObj.Generation -ge 2) {
    Write-LogWarning "      VM '$VMName' e Gen$($vmObj.Generation): COM1->Named Pipe costuma nao funcionar (use VM Gen1 / PROJETOVM_VMGeneration=1, ou relatorio so por Guest Service)."
    Add-LogLine -Path $HostLogPath -Value "WARNING: Gen$($vmObj.Generation) VM -- serial pipe transport often unavailable"
}

Write-LogHost "=== Orquestração Sandbox Hyper-V ==="
Write-LogHost "Amostra: $SamplePath"
Write-LogHost "Hash SHA256: $sampleSha256"
Write-LogHost "Relatório: $ReportOutputPath"
Write-LogHost ""

# Credenciais para PowerShell Direct (evita popup e melhora diagnóstico)
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# 1) Nome do pipe único por run (evita conflitos)
$RunPipeName = ($PipeName + "_" + $RunId) -replace "[^A-Za-z0-9_\-\.]", "_"
Add-LogLine -Path $HostLogPath -Value "Pipe name: $RunPipeName"

# 2) Iniciar listener do pipe EM PARALELO com a restauração do snapshot
# O Named Pipe tem de existir no host antes da VM arrancar, senão o Hyper-V
# não consegue ligar o COM1 ao pipe e a VM recebe sempre respostas vazias.
Write-LogHost "[2/7] A iniciar receptor do relatório (Named Pipe) em background..."
$modulePath = Join-Path $PSScriptRoot "SandboxCommon.psm1"
# Com o envio simplificado (linha-a-linha) a transmissão pode demorar bastante.
# Dar margem generosa para evitar timeouts prematuros.
$pipeTimeoutSeconds = $TimeoutSeconds + 900

$pipeJob = Start-Job -ScriptBlock {
    param($PipeName, $OutputPath, $TimeoutSecondsLocal, $ModulePath)
    Write-Host "[PIPE] Job worker arrancou pid=$PID utc=$([DateTime]::UtcNow.ToString('o'))"
    Import-Module $ModulePath -DisableNameChecking -ErrorAction Stop
    return (Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds $TimeoutSecondsLocal)
} -ArgumentList $RunPipeName, $ReportOutputPath, $pipeTimeoutSeconds, $modulePath

Add-LogLine -Path $HostLogPath -Value "Pipe job started: Id=$($pipeJob.Id) Name=$($pipeJob.Name) path=\\.\pipe\$RunPipeName timeout=${pipeTimeoutSeconds}s"
Write-LogHost "      [PIPE-HOST] Job receptor id=$($pipeJob.Id) pipe=\\.\pipe\$RunPipeName (logs [PIPE] vêm do job)"
# Margem para o job arrancar e o pipe ficar genuinamente em escuta antes do restore/arranque da VM.
Start-Sleep -Seconds 2
Write-LogHost "      Receptor do relatório iniciado (background)."

# 3) Restaurar snapshot limpo
Write-LogHost "[3/7] A restaurar snapshot '$SnapshotName'..."
Stop-SandboxVM -VMName $VMName
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot restaurado."

# 3.5) IMPORTANTE: configurar o pipe no COM1 após o restore, antes de arrancar a VM
try {
    Set-VMComPort -VMName $VMName -Number 1 -Path "\\.\pipe\$RunPipeName" -ErrorAction Stop
    Add-LogLine -Path $HostLogPath -Value "COM1 pipe set to: \\.\pipe\$RunPipeName"
    Write-LogHost "[3.5/7] Pipe configurado: \\.\pipe\$RunPipeName"
} catch {
    Add-LogLine -Path $HostLogPath -Value "Failed to set VM COM1 pipe: $_"
    Write-Warning "      Falha ao configurar COM1 pipe: $_"
}

# 4) Arrancar VM (espera pelo arranque = PowerShell Direct, sem sleep fixo)
Write-LogHost "[4/7] A arrancar a VM..."
$psDirectOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds -LogPath $HostLogPath
if ($psDirectOk -is [pscredential]) {
    $cred = $psDirectOk
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct ready with credential: $($cred.UserName)"
} else {
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct timeout/not ready"
    Write-Warning "      PowerShell Direct não ficou pronto após timeout. A continuar com cautela..."
}

# 5) Ativar Guest Service para Copy-VMFile (e opcionalmente Invoke-Command)
Write-LogHost "[5/7] A ativar Guest Service para transferência..."
Enable-SandboxGuestService -VMName $VMName
$null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120

# 6) Copiar amostra e scripts para a VM
Write-LogHost "[6/7] A copiar amostra para a VM..."
# Garantir que o diretório existe na VM
try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($Path)
        if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    } -ArgumentList $VMScriptsPath -ErrorAction SilentlyContinue
} catch { }

Copy-SandboxVMFile -VMName $VMName -SourcePath $SamplePath -DestinationPath $VMSamplePath

# Preflight: garantir que o ficheiro na VM existe e é o mesmo (SHA256) e que parece executável PE.
Write-LogHost "      A validar amostra dentro da VM (existência + SHA256 + header PE)..."
try {
    $vmCheck = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($PathLocal)
        $out = @{
            exists = $false
            sha256 = ""
            length = 0
            pe_ok = $false
            pe_reason = ""
            pe_machine = ""
        }
        if (-not (Test-Path -LiteralPath $PathLocal)) { return $out }
        $out.exists = $true
        try {
            $fi = Get-Item -LiteralPath $PathLocal -ErrorAction Stop
            $out.length = [int64]$fi.Length
        } catch { }
        try {
            $h = Get-FileHash -LiteralPath $PathLocal -Algorithm SHA256 -ErrorAction Stop
            $out.sha256 = $h.Hash
        } catch { }
        try {
            $fs = [System.IO.File]::Open($PathLocal, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $br = New-Object System.IO.BinaryReader($fs)
                $mz = $br.ReadUInt16()
                if ($mz -ne 0x5A4D) { $out.pe_ok = $false; $out.pe_reason = "Sem header MZ."; return $out }
                $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
                $peOff = $br.ReadUInt32()
                $fs.Seek([int64]$peOff, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sig = $br.ReadUInt32()
                if ($sig -ne 0x00004550) { $out.pe_ok = $false; $out.pe_reason = "Sem assinatura PE\\0\\0."; return $out }
                $machine = $br.ReadUInt16()
                $out.pe_ok = $true
                $out.pe_machine = switch ($machine) {
                    0x014c { "x86" }
                    0x8664 { "x64" }
                    0x01c4 { "ARM" }
                    0xAA64 { "ARM64" }
                    default { ("0x{0:X4}" -f $machine) }
                }
            } finally {
                try { $fs.Dispose() } catch { }
            }
        } catch {
            $out.pe_ok = $false
            $out.pe_reason = $_.Exception.Message
        }
        return $out
    } -ArgumentList $VMSamplePath -ErrorAction Stop

    if (-not $vmCheck.exists) { throw "Amostra não existe na VM em: $VMSamplePath" }
    if (-not $vmCheck.sha256 -or ($vmCheck.sha256.ToUpperInvariant() -ne $sampleSha256.ToUpperInvariant())) {
        throw "SHA256 não coincide dentro da VM. Esperado=$sampleSha256 Atual=$($vmCheck.sha256)"
    }
    if (-not $vmCheck.pe_ok) {
        throw "Amostra copiada mas não parece PE executável: $($vmCheck.pe_reason)"
    }
    Add-LogLine -Path $HostLogPath -Value "VM sample OK: len=$($vmCheck.length) sha256=$($vmCheck.sha256) machine=$($vmCheck.pe_machine)"
    Write-LogHost "      OK (machine: $($vmCheck.pe_machine))."
} catch {
    Add-LogLine -Path $HostLogPath -Value "VM sample preflight failed: $($_.Exception.Message)"
    throw
}

# Copiar scripts de análise para a VM
$scriptDir = Join-Path $PSScriptRoot "vm"
$runScript = Join-Path $scriptDir "Run-MalwareAnalysis.ps1"
$sendScript = Join-Path $scriptDir "Send-ReportViaCom.ps1"
if (Test-Path $runScript) {
    try { Copy-SandboxVMFile -VMName $VMName -SourcePath $runScript -DestinationPath "$VMScriptsPath\Run-MalwareAnalysis.ps1" } catch { 
        Write-Warning "      Falha ao copiar Run-MalwareAnalysis.ps1"
    }
}
if (Test-Path $sendScript) {
    try { Copy-SandboxVMFile -VMName $VMName -SourcePath $sendScript -DestinationPath "$VMScriptsPath\Send-ReportViaCom.ps1" } catch {
        Write-Warning "      Falha ao copiar Send-ReportViaCom.ps1"
    }
}
Write-LogHost "      Amostra e scripts copiados."

# 6) Executar análise na VM
Write-LogHost "[6/7] A executar análise na VM..."
$analysisSuccess = $false
function Invoke-RunAnalysisInVm {
    param(
        [string] $VM,
        [pscredential] $Cred,
        [string] $VmSamplePath,
        [int] $TimeoutSec,
        [string] $VmScriptDir,
        [string] $SampleSha256
    )

    $vmOutput = Invoke-Command -VMName $VM -Credential $Cred -ScriptBlock {
        param($SamplePathLocal, $TimeoutSec, $ScriptPath, $SampleSha256)
        Set-Location $ScriptPath
        & ".\Run-MalwareAnalysis.ps1" -SamplePath $SamplePathLocal -TimeoutSeconds $TimeoutSec -SampleHash $SampleSha256 -ErrorAction Stop
    } -ArgumentList $VmSamplePath, $TimeoutSec, $VmScriptDir, $SampleSha256 -ErrorAction Stop

    foreach ($l in @($vmOutput)) {
        if ($null -eq $l) { continue }
        $s = ($l | Out-String).TrimEnd()
        if (-not $s -or $s -eq "True") { continue }
        Write-LogHost ("      [VM] {0}" -f $s)
    }
}

try {
    Invoke-RunAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256
    $analysisSuccess = $true
    Add-LogLine -Path $HostLogPath -Value "Analysis executed via Invoke-Command successfully"
} catch {
    $analysisSuccess = $false
    Write-LogWarning "Invoke-Command falhou (tentativa 1): $($_.Exception.Message)"
    Add-LogLine -Path $HostLogPath -Value "Invoke-Command failed (try1): $($_.Exception.Message)"

    # Retry if VM is still up
    $vmState = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
    if ($vmState -eq 'Running') {
        Write-LogWarning "VM ainda em execução. A tentar re-invocar análise..."
        Start-Sleep -Seconds 5
        try {
            Invoke-RunAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
                -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256
            $analysisSuccess = $true
            Add-LogLine -Path $HostLogPath -Value "Analysis re-invoked successfully (try2)"
        } catch {
            Add-LogLine -Path $HostLogPath -Value "Invoke-Command failed (try2): $($_.Exception.Message)"
            Write-LogWarning "Segunda tentativa também falhou: $($_.Exception.Message)"
        }
    } else {
        Write-LogWarning "VM não está Running (estado: $vmState). Não é possível re-invocar."
    }
}

Start-Sleep -Seconds 1
$earlyState = $null
try { $earlyState = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
$pipeReportAlreadyReceived = ($earlyState -eq "Completed")
if ($pipeReportAlreadyReceived) {
    Write-LogHost "      [PIPE] Relatório já recebido durante execução da análise."
}

# 7) Aguardar o relatório via pipe
Write-LogHost "      A aguardar relatório via pipe (timeout: ${pipeTimeoutSeconds}s)..."
Add-LogLine -Path $HostLogPath -Value "Pipe wait begin: jobId=$($pipeJob.Id) earlyDone=$pipeReportAlreadyReceived analysisSuccess=$analysisSuccess"

# O pipe tem o seu próprio timeout ($pipeTimeoutSeconds); não cortar com $GlobalTimeoutSeconds.
$waitSec = $pipeTimeoutSeconds

if ($waitSec -gt 0) {
    $waitDeadline = (Get-Date).AddSeconds($waitSec)
    $lastJobLog = Get-Date
    $guestDonePath = "$VMScriptsPath\guest_analysis_done.txt"
    $guestReportPath = "C:\analysis.txt"
    while (-not $pipeReportAlreadyReceived -and (Get-Date) -lt $waitDeadline) {
        $st = $null
        try { $st = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
        if ($st -eq "Completed" -or $st -eq "Failed" -or $st -eq "Stopped") { break }

        # Puxar logs intermédios do job (drena só output novo desde a última chamada).
        try {
            $tmp = Receive-Job $pipeJob -ErrorAction SilentlyContinue 2>&1
            foreach ($item in @($tmp)) {
                $s = ($item | Out-String).TrimEnd()
                if ([string]::IsNullOrWhiteSpace($s) -or $s -eq "True") { continue }
                Write-LogHost ("      [PIPE] {0}" -f $s)
                Add-LogLine -Path $HostLogPath -Value ("[PIPE] " + $s)
            }
        } catch { }

        # Guest concluiu mas COM1/pipe nao entregou -- saida antecipada com Copy-VMFile
        if ($st -ne "Completed") {
            try {
                $guestDone = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                    param($Path)
                    Test-Path -LiteralPath $Path
                } -ArgumentList $guestDonePath -ErrorAction SilentlyContinue
                if ($guestDone -eq $true) {
                    Write-LogWarning "      Guest análise concluída ($guestDonePath) mas pipe ainda não recebeu relatório. A tentar Copy-VMFile..."
                    Add-LogLine -Path $HostLogPath -Value "Guest done detected; pipe not complete -- fallback Copy-VMFile"
                    try {
                        Copy-SandboxVMFileFromGuest -VMName $VMName -Credential $cred `
                            -GuestSourcePath $guestReportPath -HostDestinationPath $ReportOutputPath
                        if (Test-Path -LiteralPath $ReportOutputPath) {
                            Write-LogHost "      Relatório obtido via Copy-VMFile (fallback): $ReportOutputPath"
                            Add-LogLine -Path $HostLogPath -Value "Report pulled via Copy-VMFile fallback"
                            $pipeReportAlreadyReceived = $true
                            break
                        }
                    } catch {
                        Write-LogWarning "      Fallback Copy-VMFile falhou: $($_.Exception.Message)"
                        Add-LogLine -Path $HostLogPath -Value "Copy-VMFile fallback failed: $($_.Exception.Message)"
                    }
                }
            } catch { }
        }

        # Heartbeat no host a cada ~10s
        if (((Get-Date) - $lastJobLog).TotalSeconds -ge 10) {
            $remain = [int]($waitDeadline - (Get-Date)).TotalSeconds
            $pj = Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue
            $hm = if ($pj) { [string]$pj.HasMoreData } else { "?" }
            $loc = if ($pj) { [string]$pj.Location } else { "" }
            Write-LogHost "      [PIPE-HOST] job id=$($pipeJob.Id) state=$st hasMoreData=$hm loc='$loc' resto~${remain}s"
            Add-LogLine -Path $HostLogPath -Value "PIPE-HOST heartbeat state=$st hasMore=$hm rest=${remain}s"
            $lastJobLog = Get-Date
        }

        Start-Sleep -Seconds 2
    }

    $jobCompleted = $false
    try {
        $st2 = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State
        $jobCompleted = ($st2 -eq "Completed")
    } catch { }

    if (-not $jobCompleted) {
        if (-not $pipeReportAlreadyReceived) {
            Write-LogWarning "      Listener do pipe não terminou a tempo (timeout após ${waitSec}s)."
            Add-LogLine -Path $HostLogPath -Value "Pipe listener timeout after ${waitSec}s"
        }
        Stop-Job $pipeJob -ErrorAction SilentlyContinue
    }
} else {
    Write-LogWarning "      Sem tempo restante para aguardar relatório."
    Add-LogLine -Path $HostLogPath -Value "No time remaining for report"
}

# Recolher resultado do pipe
$pipeResult = $null
$pipeState = $null
try { 
    $pipeState = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State 
} catch { }

if ($pipeState -eq "Completed") {
    $pipeResult = Receive-Job $pipeJob -ErrorAction SilentlyContinue
    Remove-Job $pipeJob -Force -ErrorAction SilentlyContinue
    Add-LogLine -Path $HostLogPath -Value "Pipe lines received: $pipeResult"
    if (Test-Path $ReportOutputPath) {
        Write-LogHost "      Relatório recebido via pipe: $ReportOutputPath"
        Add-LogLine -Path $HostLogPath -Value "Report received successfully via pipe"

        if (-not (Test-ReportLooksComplete -Path $ReportOutputPath)) {
            Write-LogWarning "      Relatório via pipe parece incompleto (verificar manualmente: $ReportOutputPath)."
            Add-LogLine -Path $HostLogPath -Value "Pipe report appears incomplete"
        }
    } else {
        Write-LogWarning "      Pipe concluído mas ficheiro de relatório não encontrado."
        Add-LogLine -Path $HostLogPath -Value "Pipe completed but report file not found"
    }
} elseif (Test-Path -LiteralPath $ReportOutputPath) {
    Write-LogHost "      Relatório obtido via fallback (Copy-VMFile), pipe estado=$pipeState"
    Add-LogLine -Path $HostLogPath -Value "Report from Copy-VMFile fallback; pipe state=$pipeState"
} else {
    Write-LogWarning "      Listener do pipe não completou (estado=$pipeState). O relatório não foi obtido."
    Add-LogLine -Path $HostLogPath -Value "Pipe state=$pipeState; report not obtained"

    # Tentar obter output de erro do job para diagnóstico
    try {
        $jobErrors = Receive-Job $pipeJob -ErrorAction SilentlyContinue 2>&1
        if ($jobErrors) {
            Add-LogLine -Path $HostLogPath -Value "Pipe job output: $jobErrors"
            Write-LogWarning "      Detalhes do erro do pipe: $jobErrors"
        }
    } catch { }
    try { Stop-Job $pipeJob -ErrorAction SilentlyContinue } catch { }
    try { Remove-Job $pipeJob -Force -ErrorAction SilentlyContinue } catch { }
}

# 8) Parar VM e restaurar snapshot
Write-LogHost "[8/8] A parar a VM e a restaurar snapshot..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Milliseconds 500
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      VM restaurada ao estado limpo."

Add-LogLine -Path $HostLogPath -Value "VM stopped and snapshot restored"

# Desativar Guest Service Interface após a execução para reduzir superfície de ataque
try {
    Disable-SandboxGuestService -VMName $VMName
    Add-LogLine -Path $HostLogPath -Value "Guest Service Interface disabled after run"
} catch {
    Add-LogLine -Path $HostLogPath -Value "Failed to disable Guest Service Interface: $_"
}

# JSON estruturado do run
$analysisEnd = Get-Date
$status = if (Test-Path $ReportOutputPath) { "ok" } else { "failed" }
$jsonData = @{
    run_id         = $RunId
    sample_path    = $SamplePath
    sample_sha256  = $sampleSha256
    vm_name        = $VMName
    snapshot       = $SnapshotName
    analysis_start = $analysisStart.ToString("yyyy-MM-dd HH:mm:ss")
    analysis_end   = $analysisEnd.ToString("yyyy-MM-dd HH:mm:ss")
    report_path    = $ReportOutputPath
    report_lines   = $pipeResult
    status         = $status
}
try {
    $jsonData | ConvertTo-Json -Depth 4 | Set-Content -Path $HostJsonPath -Encoding UTF8
} catch { }

Write-LogHost ""
try { Set-Clipboard -Value $ReportOutputPath } catch { }
Write-LogHost "Concluído."
Write-LogHost "Relatório (copiado para clipboard): $ReportOutputPath"