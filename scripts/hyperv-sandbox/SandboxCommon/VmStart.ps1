function Test-SandboxVmHostLowMemoryError {
    param([object] $Err)
    if (-not $Err) { return $false }
    $ex = $null
    $text = ""
    if ($Err -is [Management.Automation.ErrorRecord]) {
        $ex = $Err.Exception
        $text = [string]$Err.Exception.Message
        if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) {
            $text += " " + [string]$Err.ErrorDetails.Message
        }
    } elseif ($Err -is [System.Exception]) {
        $ex = $Err
        $text = [string]$Err.Message
    } else {
        return $false
    }
    $wordPattern = "0x800705AA|0x8007000E|recursos de sistema|insufficient system resources|not enough memory|cannot allocate|mem[óo]ria insuficiente|n[aã]o existe mem[óo]ria|out of memory"
    while ($ex) {
        $m = [string]$ex.Message
        $text += " $m"
        if ($m -match $wordPattern) { return $true }
        try {
            $u = [uint32]$ex.HResult
            if ($u -eq 0x800705AA -or $u -eq 0x8007000E) { return $true }
        } catch { }
        $ex = $ex.InnerException
    }
    if ($text -match $wordPattern) { return $true }
    return $false
}

function Start-SandboxVM {
    param(
        [string] $VMName,
        [int]    $BootWaitSeconds = 60,
        [switch] $WaitForPowerShellDirect,
        [pscredential] $Credential,
        [pscredential[]] $CredentialCandidates,
        [int]    $PowerShellDirectTimeoutSeconds = 0,
        [string] $LogPath
    )
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        throw "VM '$VMName' n-o encontrada."
    }
    if ($vm.State -ne "Running") {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Arrancaria a VM '$VMName'."
        } else {
            $started = $false
            $changedStartup = $false
            $originalStartupBytes = $null
            $originalMinBytes = $null
            $originalMaxBytes = $null
            $originalDyn = $false
            try {
                Start-VM -Name $VMName -ErrorAction Stop | Out-Null
                $started = $true
            } catch {
                $firstErr = $_
                if (-not (Test-SandboxVmHostLowMemoryError $firstErr)) { throw }

                # Best-effort: reduzir StartupBytes (e Minimum se DynamicMemory) e re-tentar.
                try {
                    $snapMem = Get-VMMemory -VMName $VMName -ErrorAction Stop
                    $originalStartupBytes = [int64]$snapMem.Startup
                    $originalMinBytes = [int64]$snapMem.Minimum
                    $originalMaxBytes = [int64]$snapMem.Maximum
                    $originalDyn = [bool]$snapMem.DynamicMemoryEnabled
                } catch {
                    $originalStartupBytes = $null
                    $originalMinBytes = $null
                    $originalMaxBytes = $null
                    $originalDyn = $false
                }

                $candidates = New-Object System.Collections.Generic.List[long]
                if ($originalStartupBytes -and $originalStartupBytes -gt 0) {
                    foreach ($mib in @(1536, 1408, 1280, 1152, 1024, 896, 768)) {
                        $b = [int64]$mib * 1MB
                        if ($b -lt $originalStartupBytes) { [void]$candidates.Add($b) }
                    }
                } else {
                    foreach ($mib in @(1536, 1280, 1152, 1024, 896, 768)) { [void]$candidates.Add([int64]$mib * 1MB) }
                }

                foreach ($startupBytes in $candidates) {
                    try {
                        Write-LogWarning "Start-VM falhou por falta de RAM no host. A ajustar RAM (startup $([math]::Round($startupBytes / 1MB)) MiB) e a re-tentar..."
                        try {
                            $cur = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                            if ($cur -and $cur.State -ne 'Off') {
                                Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                            $deadline = (Get-Date).AddSeconds(15)
                            while ((Get-Date) -lt $deadline) {
                                $cur = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                                if (-not $cur -or $cur.State -eq 'Off') { break }
                                Start-Sleep -Milliseconds 500
                            }
                        } catch { }

                        $setOk = $false
                        for ($attempt = 1; $attempt -le 2; $attempt++) {
                            try {
                                $curMem = Get-VMMemory -VMName $VMName -ErrorAction Stop
                                if ($curMem.DynamicMemoryEnabled) {
                                    $minB = [Math]::Min([int64]$curMem.Minimum, $startupBytes)
                                    $floorB = 512MB
                                    if ($minB -lt $floorB) { $minB = $floorB }
                                    if ($minB -gt $startupBytes) { $minB = $startupBytes }
                                    $maxB = [Math]::Max([int64]$curMem.Maximum, $startupBytes)
                                    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes $minB -StartupBytes $startupBytes -MaximumBytes $maxB -ErrorAction Stop | Out-Null
                                } else {
                                    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $startupBytes -ErrorAction Stop | Out-Null
                                }
                                $setOk = $true
                                break
                            } catch {
                                $setMsg = $_.Exception.Message
                                if ($setMsg -match 'estado atual|current state|InvalidState') {
                                    try { Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
                                    Start-Sleep -Milliseconds 900
                                    continue
                                }
                                throw
                            }
                        }
                        if (-not $setOk) { throw "Set-VMMemory falhou (StartupBytes=$startupBytes): VM não ficou em estado 'Off'." }
                        $changedStartup = $true
                        Start-VM -Name $VMName -ErrorAction Stop | Out-Null
                        $started = $true
                        Write-LogHost "VM '$VMName' arrancou após ajustar Startup RAM para $([math]::Round($startupBytes / 1MB)) MiB."
                        break
                    } catch {
                        if (-not (Test-SandboxVmHostLowMemoryError $_)) { throw }
                    }
                }

                if (-not $started) {
                    if ($changedStartup -and $null -ne $originalStartupBytes -and $originalStartupBytes -gt 0) {
                        try {
                            if ($originalDyn -and $null -ne $originalMinBytes -and $null -ne $originalMaxBytes) {
                                Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes $originalMinBytes -StartupBytes $originalStartupBytes -MaximumBytes $originalMaxBytes -ErrorAction SilentlyContinue | Out-Null
                            } else {
                                Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $originalStartupBytes -ErrorAction SilentlyContinue | Out-Null
                            }
                        } catch { }
                    }
                    throw $firstErr
                }
            }
        }
    }

    if ($script:DryRun) { return }

    # Espera pelo arranque: com credenciais usa PowerShell Direct (mesma lógica que -WaitForPowerShellDirect)
    $usePsDirect = ($WaitForPowerShellDirect -or $Credential -or ($CredentialCandidates -and $CredentialCandidates.Count -gt 0))
    if ($usePsDirect) {
        if (-not $Credential -and (-not $CredentialCandidates -or $CredentialCandidates.Count -eq 0)) {
            throw "Start-SandboxVM: espera por PowerShell Direct requer -Credential ou -CredentialCandidates (ou use apenas -BootWaitSeconds sem credenciais)."
        }
        # Espera sem timeout: aguardar indefinidamente até o PowerShell Direct ficar OK.
        Write-LogHost "A aguardar arranque da VM (PowerShell Direct, verificação a cada 2s, sem timeout)..."
        return (Wait-VMPowerShellDirectReady -VMName $VMName -Credential $Credential -CredentialCandidates $CredentialCandidates -TimeoutSeconds 0 -LogPath $LogPath -LogIntervalSeconds 2)
    }

    Write-LogHost "A aguardar $BootWaitSeconds s pelo arranque da VM (sem credenciais: espera fixa)..."
    Start-Sleep -Seconds $BootWaitSeconds
}

function Wait-SandboxGuestServiceReady {
    param(
        [string] $VMName,
        [int] $TimeoutSeconds = 120
    )
    if ($script:DryRun) { return $true }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $svcName = Get-SandboxGuestServiceName -VMName $VMName
            if (-not $svcName) { return $false }
            $svc = Get-VMIntegrationService -VMName $VMName -Name $svcName -ErrorAction SilentlyContinue
            # Em alguns hosts, os campos são PrimaryStatusDescription/SecondaryStatusDescription
            $enabled = $svc -and $svc.Enabled
            $ok = $false
            if ($svc) {
                $ok = ($svc.PrimaryStatusDescription -eq "OK" -or $svc.PrimaryStatusDescription -eq "Operational") -and
                      ($svc.SecondaryStatusDescription -eq "OK" -or [string]::IsNullOrWhiteSpace($svc.SecondaryStatusDescription))
            }

            if ($enabled -and $ok) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 750
    }
    return $false
}
