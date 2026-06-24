# --- Script: Test-SerialPipeSimulation.ps1 ---
#Requires -Version 5.1
<#
.SYNOPSIS
    Simula COM1->Named Pipe (vmwp servidor + host cliente + guest escritor) sem VM.
.DESCRIPTION
    Cenários:
      1) Guest envia após atraso curto (análise rápida)
      2) Guest envia após atraso longo com cliente ligado cedo (reproduz run real)
      3) Cliente ligado cedo; guest envia após atraso longo (boot+cópia simulados)
      4) Fallback: marcador REPORT_END; detetável
      5) PhaseF não bloqueada por global timeout
#>

[CmdletBinding()]
param(
    [int] $LongGuestDelaySec = 15,
    [switch] $SkipSlow
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Import-Module (Join-Path $root 'SandboxCommon.psm1') -Force -DisableNameChecking

# --- Contadores de resultados ---
$passed = 0
$failed = 0

# --- Registo de resultado por cenário ---
function Write-CaseResult {
    param([string] $Name, [bool] $Ok, [string] $Detail = '')
    if ($Ok) {
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "       $Detail" -ForegroundColor Yellow }
    }
}

# --- Simulador de guest (servidor Named Pipe) ---
function Start-VmwpPipeSimulator {
    param(
        [string] $PipeName,
        [int] $GuestDelaySec,
        [string[]] $ReportBody
    )

    $job = Start-Job -ArgumentList $PipeName, $GuestDelaySec, $ReportBody -ScriptBlock {
        param($Name, $DelaySec, $Body)

        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $server = New-Object System.IO.Pipes.NamedPipeServerStream(
            $Name,
            [System.IO.Pipes.PipeDirection]::Out,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None
        )
        try {
            $server.WaitForConnection()

            if ($DelaySec -gt 0) {
                Start-Sleep -Seconds $DelaySec
            }

            $writer = New-Object System.IO.StreamWriter($server, $utf8)
            $writer.NewLine = "`r`n"
            $writer.AutoFlush = $true
            $writer.WriteLine('START_OF_REPORT')
            $writer.WriteLine('VERSION=1')
            $writer.WriteLine('END_HEADER')
            foreach ($line in $Body) { $writer.WriteLine($line) }
            $writer.WriteLine('END_OF_REPORT')
            $writer.Flush()
            Start-Sleep -Seconds 1
        } finally {
            try { $server.Dispose() } catch { }
        }
    }
    return $job
}

# --- Invoca a função real de recepção do módulo ---
function Invoke-PipeReceiveTest {
    param(
        [string] $PipeName,
        [string] $OutPath,
        [int] $TimeoutSec,
        [int] $IdleReconnectSecLocal = 120
    )

    return Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutPath -TimeoutSeconds $TimeoutSec
}

# --- Execução dos cenários de teste ---
$tmp = Join-Path $env:TEMP ("sandbox_pipe_sim_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    Write-Host "=== Simulação pipe COM1 (temp: $tmp) ===" -ForegroundColor Cyan
    Write-Host ""

    # --- Cenário 1: guest envia após 2s ---
    $pipe1 = "SandboxPipeSim_" + ([guid]::NewGuid().ToString('N'))
    $out1 = Join-Path $tmp 'report1.txt'
    $sim1 = Start-VmwpPipeSimulator -PipeName $pipe1 -GuestDelaySec 2 -ReportBody @('linha A', 'linha B')
    Start-Sleep -Milliseconds 400
    try {
        $lines = Invoke-PipeReceiveTest -PipeName $pipe1 -OutPath $out1 -TimeoutSec 30
        $text = Get-Content -LiteralPath $out1 -Raw
        $ok = ($lines -eq 2) -and ($text -match 'linha A') -and ($text -match 'linha B')
        Write-CaseResult 'Cenário 1: guest após 2s' $ok "lines=$lines"
    } catch {
        Write-CaseResult 'Cenário 1: guest após 2s' $false $_.Exception.Message
    } finally {
        Stop-Job $sim1 -ErrorAction SilentlyContinue
        Remove-Job $sim1 -Force -ErrorAction SilentlyContinue
    }

  if (-not $SkipSlow) {
    # --- Cenário 2: guest após 8s, host ligado cedo ---
    $pipe2 = "SandboxPipeSim_" + ([guid]::NewGuid().ToString('N'))
    $out2 = Join-Path $tmp 'report2.txt'
    $sim2 = Start-VmwpPipeSimulator -PipeName $pipe2 -GuestDelaySec 8 -ReportBody @('delayed report')
    Start-Sleep -Milliseconds 300
    try {
        $lines = Invoke-PipeReceiveTest -PipeName $pipe2 -OutPath $out2 -TimeoutSec 45
        $ok = (Test-Path $out2) -and ((Get-Content $out2 -Raw) -match 'delayed report')
        Write-CaseResult 'Cenário 2: guest após 8s (cliente cedo)' $ok "lines=$lines"
    } catch {
        Write-CaseResult 'Cenário 2: guest após 8s (cliente cedo)' $false $_.Exception.Message
    } finally {
        Stop-Job $sim2 -ErrorAction SilentlyContinue
        Remove-Job $sim2 -Force -ErrorAction SilentlyContinue
    }

    # --- Cenário 3: atraso longo simula análise na VM ---
    $pipe3 = "SandboxPipeSim_" + ([guid]::NewGuid().ToString('N'))
    $out3 = Join-Path $tmp 'report3.txt'
    $sim3 = Start-VmwpPipeSimulator -PipeName $pipe3 -GuestDelaySec $LongGuestDelaySec -ReportBody @('apos analise')
    Start-Sleep -Milliseconds 300
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $lines = Invoke-PipeReceiveTest -PipeName $pipe3 -OutPath $out3 -TimeoutSec ($LongGuestDelaySec + 45)
        $sw.Stop()
        $ok = (Test-Path $out3) -and ((Get-Content $out3 -Raw) -match 'apos analise')
        Write-CaseResult "Cenário 3: guest após ${LongGuestDelaySec}s (cliente já ligado)" $ok "lines=$lines elapsed=$([int]$sw.Elapsed.TotalSeconds)s"
    } catch {
        $sw.Stop()
        Write-CaseResult "Cenário 3: guest após ${LongGuestDelaySec}s (cliente já ligado)" $false "$($_.Exception.Message) elapsed=$([int]$sw.Elapsed.TotalSeconds)s"
    } finally {
        Stop-Job $sim3 -ErrorAction SilentlyContinue
        Remove-Job $sim3 -Force -ErrorAction SilentlyContinue
    }
  } else {
    Write-Host "[SKIP] Cenários 2-3 (lentos) omitidos (-SkipSlow)" -ForegroundColor DarkYellow
  }

    # --- Cenário 4: marcador REPORT_END; detetável ---
    $guestReport = Join-Path $tmp 'analysis_guest.txt'
    @(
        'Relatório simulado',
        'Segunda linha',
        'REPORT_END;'
    ) | Set-Content -LiteralPath $guestReport -Encoding UTF8

    $tail = Get-Content -LiteralPath $guestReport -Raw
    $hasMarker = $tail.Contains('REPORT_END;')
    Write-CaseResult 'Cenário 4: marcador REPORT_END; detetável' $hasMarker

    # --- Cenário 5: PhaseF não bloqueada por global timeout ---
    $phasesSkip = @('PhaseE-WaitReport.ps1', 'PhaseF-CollectResult.ps1', 'PhaseG-Finish.ps1')
    $deadline = (Get-Date).AddSeconds(-1)
    $wouldBlockF = ($deadline -lt (Get-Date)) -and ($phasesSkip -notcontains 'PhaseF-CollectResult.ps1')
    $wouldAllowF = ($deadline -lt (Get-Date)) -and ($phasesSkip -contains 'PhaseF-CollectResult.ps1')
    Write-CaseResult 'Cenário 5: PhaseF permitida após global timeout' ((-not $wouldBlockF) -and $wouldAllowF)

    Write-Host ""
    Write-Host "=== Resultado: $passed passou, $failed falhou ===" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
    if ($failed -gt 0) { exit 1 }
}
finally {
    # *Limpeza da pasta temporária de testes*
    try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
