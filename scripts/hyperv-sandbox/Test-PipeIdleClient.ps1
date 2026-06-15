# Cliente ligado cedo; guest só envia após N segundos (reproduz run 20260612_175346)
param([int] $GuestDelaySec = 15)

Remove-Item Env:PROJETOVM_PipeIdleReconnectSec -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'SandboxCommon.psm1') -Force

$pipe = 'SandboxPipeIdle_' + [guid]::NewGuid().ToString('N')
$out = Join-Path $env:TEMP 'pipe_idle_client_test.txt'

$job = Start-Job -ArgumentList $pipe, $GuestDelaySec -ScriptBlock {
    param($Name, $Delay)
    $s = New-Object System.IO.Pipes.NamedPipeServerStream(
        $Name, [System.IO.Pipes.PipeDirection]::Out, 1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::None)
    $s.WaitForConnection()
    Start-Sleep -Seconds $Delay
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $w = New-Object System.IO.StreamWriter($s, $utf8)
    $w.NewLine = "`r`n"; $w.AutoFlush = $true
    $w.WriteLine('START_OF_REPORT')
    $w.WriteLine('END_HEADER')
    $w.WriteLine("payload after ${Delay}s idle")
    $w.WriteLine('END_OF_REPORT')
    Start-Sleep -Seconds 1
    $s.Dispose()
}

Start-Sleep -Milliseconds 300
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $n = Receive-SandboxReportFromPipe -PipeName $pipe -OutputPath $out -TimeoutSeconds ($GuestDelaySec + 60)
    $sw.Stop()
    $ok = (Test-Path $out) -and ((Get-Content $out -Raw) -match 'payload after')
    if ($ok) {
        Write-Host "[PASS] Guest apos ${GuestDelaySec}s idle no cliente (elapsed=$([int]$sw.Elapsed.TotalSeconds)s sessions ok)"
        exit 0
    }
    Write-Host "[FAIL] Ficheiro invalido lines=$n"
    exit 1
} catch {
    $sw.Stop()
    Write-Host "[FAIL] $($_.Exception.Message) elapsed=$([int]$sw.Elapsed.TotalSeconds)s"
    exit 1
} finally {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}
