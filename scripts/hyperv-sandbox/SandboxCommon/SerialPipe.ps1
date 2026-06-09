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

function New-SandboxNamedPipeServer {
    param(
        [string] $PipeName,
        [int]    $InBufferSize = 4096,
        [int]    $OutBufferSize = 4096
    )
    $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity

    # DACL explícito: não basta Administradores — o worker do Hyper-V que liga o COM1 da VM
    # ao named pipe corre como SYSTEM / contas de VM; sem estas regras WaitForConnection()
    # pode ficar bloqueado para sempre enquanto o guest acredita que escreveu com sucesso.
    foreach ($sidString in @(
            "S-1-5-32-544",  # BUILTIN\Administrators
            "S-1-5-18",      # NT AUTHORITY\SYSTEM
            "S-1-5-83-0"     # NT VIRTUAL MACHINE\Virtual Machines (Hyper-V)
        )) {
        try {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($sidString)
            $acct = $sid.Translate([System.Security.Principal.NTAccount]).Value
            $rule = New-Object System.IO.Pipes.PipeAccessRule(
                $acct,
                [System.IO.Pipes.PipeAccessRights]::FullControl,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $pipeSecurity.AddAccessRule($rule)
        } catch {
            # SIDs opcionais podem falhar em SO antigos — ignorar silenciosamente
        }
    }

    # Várias instâncias (>1) evitam ERROR_PIPE_BUSY
    $pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
        $PipeName,
        [System.IO.Pipes.PipeDirection]::In,
        254,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::None,
        $InBufferSize,
        $OutBufferSize,
        $pipeSecurity
    )
    return $pipe
}

function Receive-SandboxReportFromPipe {
    param(
        [string] $PipeName,
        [string] $OutputPath,
        [int]    $TimeoutSeconds = 600
    )

    $pipe = $null
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        Write-Host "[PIPE] ---- inicio receptor pid=$PID utc=$([DateTime]::UtcNow.ToString('o')) pipe='$PipeName' timeout=${TimeoutSeconds}s out='$OutputPath'"

        # Tentativa 1: como servidor
        $useClient = $false
        try {
            $pipe = New-SandboxNamedPipeServer -PipeName $PipeName
            Write-Host "[PIPE] Servidor criado (NamedPipeServerStream In). Nome curto: '$PipeName'"
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match "ocupad|busy") {
                $useClient = $true
                Write-Host "[PIPE] Servidor ocupado, a tentar como cliente..."
            } else {
                throw
            }
        }

        # Se necessário, ligar como cliente
        if ($useClient) {
            $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::In)
            while (-not $pipe.IsConnected -and ([DateTime]::UtcNow -lt $deadline)) {
                try {
                    $remainingMs = [int][Math]::Max(100, [Math]::Min(2000, ($deadline - [DateTime]::UtcNow).TotalMilliseconds))
                    $pipe.Connect($remainingMs)
                } catch {
                    Start-Sleep -Milliseconds 200
                }
            }
            if (-not $pipe.IsConnected) { throw "Timeout ao ligar como client ao pipe '$PipeName'." }
            Write-Host "[PIPE] Cliente ligado ao pipe: $PipeName"
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try { $pipe.ReadTimeout = 1000 } catch { }

        $inReport = $false
        $reportLines = @()
        $seenAny = $false
        $lastProgress = [DateTime]::UtcNow
        $rxLines = 0
        $reader = $null
        $gotEndOfReport = $false
        # Após WaitForConnection, o worker do Hyper-V pode reportar IsConnected=$false brevemente antes do guest abrir COM1.
        $connectEstablishedUtc = $null
        $lastEscutaLogUtc = [DateTime]::MinValue
        $acceptCount = 0
        $lastGraceLogUtc = [DateTime]::MinValue
        $disconnectCount = 0

        # Servidor: o Hyper-V pode ligar ao pipe cedo e fechar antes do guest abrir COM1 para enviar.
        # Nesse caso é preciso Disconnect + novo WaitForConnection; uma única aceitação fica à espera sem dados.
        while ([DateTime]::UtcNow -lt $deadline -and -not $gotEndOfReport) {
            if (-not $useClient -and $null -eq $reader) {
                $nowListen = [DateTime]::UtcNow
                if (($nowListen - $lastEscutaLogUtc).TotalSeconds -ge 25) {
                    $remListen = [int]($deadline - $nowListen).TotalSeconds
                    Write-Host "[PIPE] À escuta (WaitForConnection) pipe='$PipeName' restante~${remListen}s aceitesAnteriores=$acceptCount disconnects=$disconnectCount"
                    $lastEscutaLogUtc = $nowListen
                }
                $pipe.WaitForConnection()
                $acceptCount++
                $connectEstablishedUtc = [DateTime]::UtcNow
                Write-Host "[PIPE] WaitForConnection OK #$acceptCount utc=$($connectEstablishedUtc.ToString('o')) IsConnected=$($pipe.IsConnected) useClient=$useClient"
                $reader = New-Object System.IO.StreamReader($pipe, $utf8NoBom, $false)
                Write-Host "[PIPE] StreamReader criado; a ler linhas (ReadTimeout=$($pipe.ReadTimeout)ms)"
            } elseif ($useClient -and $null -eq $reader) {
                $reader = New-Object System.IO.StreamReader($pipe, $utf8NoBom, $false)
                $connectEstablishedUtc = [DateTime]::UtcNow
                Write-Host "[PIPE] Modo cliente: StreamReader criado utc=$($connectEstablishedUtc.ToString('o'))"
            }

            $raw = $null
            try {
                $raw = $reader.ReadLine()
            } catch [System.IO.IOException] {
                # Timeout de leitura – continua
                $raw = $null
            } catch {
                throw
            }

            if ($null -ne $raw) {
                $seenAny = $true
                $rxLines++
                $line = ($raw -replace "`0", "").Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                if ($line -eq "START_OF_REPORT") {
                    $inReport = $true
                    Write-Host "[PIPE] START_OF_REPORT recebido (aceitacao #$acceptCount) utc=$([DateTime]::UtcNow.ToString('o'))"
                    continue
                }

                if ($line -eq "END_OF_REPORT" -or $line -eq "END_OF_REPORT_CHECKSUM") {
                    Write-Host "[PIPE] Marcador fim: '$line' linhasCorpo=$($reportLines.Count) aceitacao#$acceptCount utc=$([DateTime]::UtcNow.ToString('o'))"
                    $gotEndOfReport = $true
                    break
                }

                if ($inReport) {
                    $reportLines += $line
                }
            }

            # Ligação fechada no lado do hypervisor/guest antes do fim do protocolo → aceitar de novo.
            if (-not $useClient -and $null -ne $reader -and (-not $pipe.IsConnected)) {
                # Não fazer Disconnect imediato: o Hyper-V liga/desliga o pipe antes do SerialPort do guest abrir.
                $postConnectGraceSec = 18
                if ($null -ne $connectEstablishedUtc -and ([DateTime]::UtcNow - $connectEstablishedUtc).TotalSeconds -lt $postConnectGraceSec) {
                    $gnow = [DateTime]::UtcNow
                    if (($gnow - $lastGraceLogUtc).TotalSeconds -ge 5) {
                        $gs = [int]($gnow - $connectEstablishedUtc).TotalSeconds
                        Write-Host "[PIPE] Graca pos-ligacao ${gs}s/${postConnectGraceSec}s IsConnected=$($pipe.IsConnected) seenAny=$seenAny rxLines=$rxLines ace#$acceptCount"
                        $lastGraceLogUtc = $gnow
                    }
                    Start-Sleep -Milliseconds 200
                    continue
                }
                # IsConnected pode ficar falso brevemente com dados ainda em buffer do StreamReader.
                $hasBuffered = $false
                $peekVal = $null
                try { $peekVal = $reader.Peek(); $hasBuffered = ($peekVal -ge 0) } catch { $hasBuffered = $false; $peekVal = "peek_erro" }
                if ($hasBuffered) {
                    Start-Sleep -Milliseconds 50
                    continue
                }
                $secSinceAccept = if ($null -ne $connectEstablishedUtc) { [int]([DateTime]::UtcNow - $connectEstablishedUtc).TotalSeconds } else { -1 }
                $disconnectCount++
                Write-Host "[PIPE] Pre-Disconnect #$disconnectCount ace#$acceptCount apos ${secSinceAccept}s seenAny=$seenAny rxLines=$rxLines inReport=$inReport peek=$peekVal"
                try { $reader.Close() } catch { }
                try { $reader.Dispose() } catch { }
                $reader = $null
                $connectEstablishedUtc = $null
                if (-not $gotEndOfReport) {
                    try { $pipe.Disconnect() } catch { }
                    $inReport = $false
                    $reportLines = @()
                    $seenAny = $false
                    $rxLines = 0
                    Write-Host "[PIPE] Pipe desligado; novo WaitForConnection (aceitacoes totais=$acceptCount disconnects=$disconnectCount)"
                }
                Start-Sleep -Milliseconds 200
                continue
            }

            # Log de progresso
            if (([DateTime]::UtcNow - $lastProgress).TotalSeconds -ge 10) {
                $remaining = [int]($deadline - [DateTime]::UtcNow).TotalSeconds
                if (-not $seenAny) {
                    Write-Host "[PIPE] Heartbeat: sem linhas brutas ainda ace#$acceptCount disc#$disconnectCount (restante ~${remaining}s)"
                } elseif (-not $inReport) {
                    Write-Host "[PIPE] Heartbeat: rxLines=$rxLines sem START_OF_REPORT ace#$acceptCount (restante ~${remaining}s)"
                } else {
                    Write-Host "[PIPE] Heartbeat: corpo $($reportLines.Count) linhas ace#$acceptCount (restante ~${remaining}s)"
                }
                $lastProgress = [DateTime]::UtcNow
            }
            Start-Sleep -Milliseconds 100
        }

        if ($null -ne $reader) {
            try { $reader.Close() } catch { }
        }
        try { $pipe.Close() } catch { }

        if ($reportLines.Count -eq 0) {
            Write-Host "[PIPE] ---- fim sem dados utc=$([DateTime]::UtcNow.ToString('o')) aceitacoes=$acceptCount disconnects=$disconnectCount seenAny=$seenAny rxLines=$rxLines gotEnd=$gotEndOfReport"
            throw "Nenhum dado recebido do pipe"
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
        Write-Host "[PIPE] Relatorio guardado: $OutputPath ($($cleanLines.Count) linhas) aceitacoes=$acceptCount disconnects=$disconnectCount utc=$([DateTime]::UtcNow.ToString('o'))"
        return $cleanLines.Count

    } catch {
        Write-Host "[PIPE] ---- excecao utc=$([DateTime]::UtcNow.ToString('o')): $($_.Exception.Message)"
        Write-Error "[PIPE] Erro: $_"
        throw
    } finally {
        if ($null -ne $pipe -and $pipe.IsConnected) {
            try { $pipe.Close() } catch { }
        }
    }
}
