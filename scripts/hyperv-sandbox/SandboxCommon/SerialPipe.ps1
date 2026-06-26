# --- Módulo: SerialPipe.ps1 ---
# --- Canal serial COM1 ↔ named pipe no host (relatório) ---

# --- Configuração de COM1 para named pipe na VM Gen1 ---
function Set-SandboxVMComPortPipe {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][string] $PipeShortName
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Configuraria COM1 -> \\.\pipe\$PipeShortName na VM '$VMName'."
        return
    }
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.Generation -ne 1) {
        throw "COM1/pipe só é suportado em VM Generation 1. VM '$VMName' é Gen$($vm.Generation)."
    }
    if ($vm.State -ne 'Off') {
        throw "A VM '$VMName' tem de estar Off para Set-VMComPort. Estado: $($vm.State)."
    }
    $path = "\\.\pipe\$PipeShortName"
    Set-VMComPort -VMName $VMName -Number 1 -Path $path -ErrorAction Stop | Out-Null
}

# --- Verificação se transporte serial é aplicável à VM ---
function Test-SandboxSerialTransportApplicable {
    param(
        [Parameter(Mandatory = $true)][string] $VMName
    )
    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        return ($vm.Generation -eq 1)
    } catch {
        return $false
    }
}

# --- Paragem de job receptor de pipe ---
function Stop-SandboxPipeReportJob {
    param(
        [Parameter(Mandatory = $true)] $PipeJob
    )
    if (-not $PipeJob) { return }
    try { Stop-Job -Job $PipeJob -ErrorAction SilentlyContinue } catch { }
    try { Remove-Job -Job $PipeJob -Force -ErrorAction SilentlyContinue } catch { }
}

# --- Limpeza de estado residual de pipes/COM1 ---
function Clear-SandboxPipeEnvironment {
    <#
    .SYNOPSIS
        Limpa estado residual de pipes/COM1 antes de um novo run (jobs orfaos, VM ligada, COM1 antigo).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [string] $LogPath = "",
        [int] $VmStopWaitSeconds = 8
    )

    function Write-PipeCleanupLog {
        param([string] $Message)
        if ($LogPath) {
            try { Add-LogLine -Path $LogPath -Value $Message } catch { }
        }
    }

    # Parar jobs órfãos de Receive-SandboxReportFromPipe
    $stoppedJobs = 0
    Get-Job -ErrorAction SilentlyContinue | ForEach-Object {
        $jb = $_
        $cmd = ""
        try { $cmd = [string]$jb.Command } catch { }
        if ($cmd -match 'Receive-SandboxReportFromPipe') {
            try { Stop-Job -Job $jb -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Job $jb -Force -ErrorAction SilentlyContinue } catch { }
            $stoppedJobs++
            Write-PipeCleanupLog "Pipe cleanup: stopped orphan receiver job Id=$($jb.Id)"
        }
    }
    if ($stoppedJobs -gt 0) {
        Write-PipeCleanupLog "Pipe cleanup: removed $stoppedJobs orphan pipe receiver job(s)"
    }

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) { return }

    # Parar VM se ligada para libertar o pipe do vmwp
    if ($vm.State -ne 'Off') {
        Write-PipeCleanupLog "Pipe cleanup: stopping VM '$VMName' (state=$($vm.State)) to release vmwp pipe"
        Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue | Out-Null
        $deadline = (Get-Date).AddSeconds($VmStopWaitSeconds)
        while ((Get-Date) -lt $deadline) {
            $stateNow = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
            if ($stateNow -eq 'Off') { break }
            Start-Sleep -Milliseconds 300
        }
        $finalState = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
        Write-PipeCleanupLog "Pipe cleanup: VM state after stop wait: $finalState"
    }

    # COM1 -> pipe descartável (VM Off) para não reutilizar mapeamento do run anterior
    if ($vm.Generation -eq 1 -and (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State -eq 'Off') {
        $discard = "SandboxReportPipe_DISCARD_" + [guid]::NewGuid().ToString('N').Substring(0, 8)
        try {
            Set-VMComPort -VMName $VMName -Number 1 -Path "\\.\pipe\$discard" -ErrorAction Stop | Out-Null
            Write-PipeCleanupLog "Pipe cleanup: COM1 reset to \\.\pipe\$discard"
        } catch {
            Write-PipeCleanupLog "Pipe cleanup: COM1 reset skipped: $($_.Exception.Message)"
        }
    }
}

# --- Recepção de relatório via named pipe (cliente Hyper-V) ---
function Receive-SandboxReportFromPipe {
    param(
        [string] $PipeName,
        [string] $OutputPath,
        [int]    $TimeoutSeconds = 600,
        [int]    $IdleReconnectSeconds = -1
    )

    # O servidor do named pipe do COM1 é criado pelo vmwp.exe quando a VM arranca.
    # O host liga-se como CLIENTE; criar NamedPipeServerStream aqui gera conflito de instâncias.

    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $configuredIdle = $IdleReconnectSeconds
        if ($configuredIdle -lt 0) {
            $configuredIdle = if ($script:PROJETOVM_PipeIdleReconnectSec -gt 0) {
                [int]$script:PROJETOVM_PipeIdleReconnectSec
            } elseif ($env:PROJETOVM_PipeIdleReconnectSec) {
                [int]$env:PROJETOVM_PipeIdleReconnectSec
            } else {
                900
            }
        }
        Write-Host "[PIPE] ---- início receptor (cliente) pid=$PID utc=$([DateTime]::UtcNow.ToString('o')) pipe='$PipeName' timeout=${TimeoutSeconds}s idleReconnect=${configuredIdle}s out='$OutputPath'"

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $reportLines = @()
        $gotEndOfReport = $false
        $connectAttempts = 0
        $sessionCount = 0
        $lastConnectLogUtc = [DateTime]::MinValue

        while ([DateTime]::UtcNow -lt $deadline -and -not $gotEndOfReport) {
            $pipe = $null
            $reader = $null
            try {
                $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::In)
                $connectAttempts++
                try {
                    $pipe.Connect(2000)
                } catch {
                    # Pipe ainda não existe (VM desligada / vmwp ainda não o criou)
                    if (([DateTime]::UtcNow - $lastConnectLogUtc).TotalSeconds -ge 25) {
                        $rem = [int]($deadline - [DateTime]::UtcNow).TotalSeconds
                        Write-Host "[PIPE] À espera do pipe do Hyper-V \\.\pipe\$PipeName (VM ligada?) tentativas=$connectAttempts restante~${rem}s"
                        $lastConnectLogUtc = [DateTime]::UtcNow
                    }
                    Start-Sleep -Milliseconds 500
                    continue
                }

                $sessionCount++
                Write-Host "[PIPE] Ligado ao pipe (cliente) sessao#$sessionCount utc=$([DateTime]::UtcNow.ToString('o')) tentativas=$connectAttempts"
                $reader = New-Object System.IO.StreamReader($pipe, $utf8NoBom, $false)

                $inReport = $false
                $rxLines = 0
                $lastProgress = [DateTime]::UtcNow
                $lastDataUtc = [DateTime]::UtcNow
                $sessionEof = $false
                $idleReconnectSeconds = $configuredIdle

                while ([DateTime]::UtcNow -lt $deadline -and -not $gotEndOfReport -and -not $sessionEof) {
                    if ($idleReconnectSeconds -gt 0 -and ([DateTime]::UtcNow - $lastDataUtc).TotalSeconds -ge $idleReconnectSeconds) {
                        Write-Host "[PIPE] Sessao#$sessionCount ociosa ${idleReconnectSeconds}s sem dados -- a religar"
                        $sessionEof = $true
                        continue
                    }
                    # Leitura assíncrona para heartbeat e respeitar deadline
                    $task = $reader.ReadLineAsync()
                    while (-not $task.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
                        try { [void]$task.Wait(500) } catch { }
                        if (([DateTime]::UtcNow - $lastProgress).TotalSeconds -ge 15) {
                            $remaining = [int]($deadline - [DateTime]::UtcNow).TotalSeconds
                            if (-not $inReport) {
                                Write-Host "[PIPE] Heartbeat: ligado, rxLines=$rxLines sem START_OF_REPORT sessao#$sessionCount (restante ~${remaining}s)"
                            } else {
                                Write-Host "[PIPE] Heartbeat: corpo $($reportLines.Count) linhas sessao#$sessionCount (restante ~${remaining}s)"
                            }
                            $lastProgress = [DateTime]::UtcNow
                        }
                    }
                    if (-not $task.IsCompleted) { break }

                    $raw = $null
                    try {
                        $raw = $task.GetAwaiter().GetResult()
                    } catch {
                        # Pipe partido (VM parada/reiniciada) — religar
                        Write-Host "[PIPE] Leitura falhou (pipe fechado?) sessao#${sessionCount}: $($_.Exception.Message)"
                        $sessionEof = $true
                        continue
                    }
                    if ($null -eq $raw) {
                        Write-Host "[PIPE] EOF na sessao#$sessionCount rxLines=$rxLines inReport=$inReport"
                        $sessionEof = $true
                        continue
                    }

                    $rxLines++
                    $lastDataUtc = [DateTime]::UtcNow
                    $line = ($raw -replace "`0", "").Trim()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    if ($line -eq "START_OF_REPORT") {
                        $inReport = $true
                        $reportLines = @()
                        Write-Host "[PIPE] START_OF_REPORT recebido (sessao#$sessionCount) utc=$([DateTime]::UtcNow.ToString('o'))"
                        continue
                    }

                    if (-not $inReport -and $line -match '^(COM1_|PIPE_)') {
                        Write-Host "[PIPE] Guest sinal: '$line' sessao#$sessionCount"
                        continue
                    }

                    if ($line -eq "END_OF_REPORT" -or $line -eq "END_OF_REPORT_CHECKSUM") {
                        Write-Host "[PIPE] Marcador fim: '$line' linhasCorpo=$($reportLines.Count) sessao#$sessionCount utc=$([DateTime]::UtcNow.ToString('o'))"
                        $gotEndOfReport = $true
                        continue
                    }

                    if ($inReport) {
                        $reportLines += $line
                    }
                }
            } finally {
                if ($null -ne $reader) {
                    try { $reader.Dispose() } catch { }
                }
                if ($null -ne $pipe) {
                    try { $pipe.Dispose() } catch { }
                }
            }

            if (-not $gotEndOfReport) {
                # Sessão terminou sem relatório completo: descartar parcial e religar
                if ($reportLines.Count -gt 0) {
                    Write-Host "[PIPE] Sessao#$sessionCount terminou com relatório incompleto ($($reportLines.Count) linhas) -- a descartar e religar"
                    $reportLines = @()
                }
                Start-Sleep -Milliseconds 300
            }
        }

        if ($reportLines.Count -eq 0 -or -not $gotEndOfReport) {
            Write-Host "[PIPE] ---- fim sem dados utc=$([DateTime]::UtcNow.ToString('o')) sessoes=$sessionCount tentativasConnect=$connectAttempts gotEnd=$gotEndOfReport linhas=$($reportLines.Count)"
            throw "Nenhum relatório completo recebido do pipe"
        }

        # --- Remoção de cabeçalho opcional do relatório ---
        $cleanLines = @()
        $skipHeader = $true
        foreach ($line in $reportLines) {
            if ($skipHeader) {
                if ($line -match "^(VERSION|TIMESTAMP|SHA256|REPORT_SIZE|CHECKSUM)=") { continue }
                if ($line -eq "END_HEADER") { $skipHeader = $false; continue }
                $skipHeader = $false
                $cleanLines += $line
            } else {
                $cleanLines += $line
            }
        }

        $content = $cleanLines -join "`r`n"
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)
        Write-Host "[PIPE] Relatório guardado: $OutputPath ($($cleanLines.Count) linhas) sessoes=$sessionCount utc=$([DateTime]::UtcNow.ToString('o'))"
        return $cleanLines.Count

    } catch {
        Write-Host "[PIPE] ---- excecao utc=$([DateTime]::UtcNow.ToString('o')): $($_.Exception.Message)"
        Write-Error "[PIPE] Erro: $_"
        throw
    }
}
