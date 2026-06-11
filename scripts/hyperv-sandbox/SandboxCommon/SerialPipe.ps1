# Canal serial COM1 (Gen1) ↔ Named Pipe no host (relatório texto, START_OF_REPORT … END_OF_REPORT)

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

function Receive-SandboxReportFromPipe {
    param(
        [string] $PipeName,
        [string] $OutputPath,
        [int]    $TimeoutSeconds = 600
    )

    # O servidor do named pipe do COM1 é criado pelo worker do Hyper-V (vmwp.exe)
    # quando a VM arranca com COM1 -> \\.\pipe\<nome>. O host tem de se ligar como
    # CLIENTE. Criar aqui um NamedPipeServerStream com o mesmo nome gera uma 2ª
    # instância do pipe: os bytes do guest vão para a instância do vmwp (sem leitor,
    # são descartados) e o WaitForConnection do nosso servidor nunca dispara.
    # O pipe só existe enquanto a VM está ligada, por isso o connect é repetido
    # até a VM arrancar; se o vmwp fechar (VM reiniciada/desligada) religa-se.

    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        Write-Host "[PIPE] ---- início receptor (cliente) pid=$PID utc=$([DateTime]::UtcNow.ToString('o')) pipe='$PipeName' timeout=${TimeoutSeconds}s out='$OutputPath'"

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
                    # Pipe ainda não existe (VM desligada / vmwp ainda não o criou) — repetir.
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
                $sessionEof = $false

                while ([DateTime]::UtcNow -lt $deadline -and -not $gotEndOfReport -and -not $sessionEof) {
                    # Leitura assíncrona para conseguir heartbeat e respeitar o deadline
                    # (PipeStream não suporta ReadTimeout em leituras síncronas).
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
                    if (-not $task.IsCompleted) { break }   # deadline atingido durante a leitura

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
                        # EOF: vmwp fechou o pipe — religar
                        Write-Host "[PIPE] EOF na sessao#$sessionCount rxLines=$rxLines inReport=$inReport"
                        $sessionEof = $true
                        continue
                    }

                    $rxLines++
                    $line = ($raw -replace "`0", "").Trim()
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    if ($line -eq "START_OF_REPORT") {
                        $inReport = $true
                        $reportLines = @()
                        Write-Host "[PIPE] START_OF_REPORT recebido (sessao#$sessionCount) utc=$([DateTime]::UtcNow.ToString('o'))"
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
                # Sessão terminou sem relatório completo: descartar parcial e religar.
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

        # Remover linhas de cabeçalho (se existirem)
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
