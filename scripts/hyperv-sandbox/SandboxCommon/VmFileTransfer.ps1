function Get-SandboxPsDirectChunkSize {
    $configured = [int]$script:PROJETOVM_PsDirectChunkSizeBytes
    if ($configured -gt 65536) { return $configured }
    return 2097152
}

function Copy-SandboxVMFileToGuestViaPsDirect {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $HostSourcePath,
        [Parameter(Mandatory = $true)][string] $GuestDestinationPath
    )

    if (-not (Test-Path -LiteralPath $HostSourcePath)) {
        throw "Ficheiro host não encontrado: $HostSourcePath"
    }

    Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
        param($Path)
        $parent = Split-Path -Parent -Path $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    } -ArgumentList $GuestDestinationPath -ErrorAction Stop

    $chunkSize = Get-SandboxPsDirectChunkSize
    $offset = 0
    $fs = [System.IO.File]::Open($HostSourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        while ($true) {
            $buffer = New-Object byte[] $chunkSize
            $read = $fs.Read($buffer, 0, $chunkSize)
            if ($read -le 0) { break }

            $data = if ($read -lt $chunkSize) {
                [Convert]::ToBase64String($buffer, 0, $read)
            } else {
                [Convert]::ToBase64String($buffer)
            }

            Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
                param($Path, $Offset, $Base64Data, $IsFirst)
                $bytes = [Convert]::FromBase64String($Base64Data)
                $mode = if ($IsFirst) { [System.IO.FileMode]::Create } else { [System.IO.FileMode]::OpenOrCreate }
                $fsOut = [System.IO.File]::Open($Path, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $null = $fsOut.Seek($Offset, [System.IO.SeekOrigin]::Begin)
                    $fsOut.Write($bytes, 0, $bytes.Length)
                } finally {
                    $fsOut.Dispose()
                }
            } -ArgumentList $GuestDestinationPath, $offset, $data, ($offset -eq 0) -ErrorAction Stop

            $offset += $read
            if ($read -lt $chunkSize) { break }
        }
    } finally {
        $fs.Dispose()
    }
}

function Copy-SandboxVMFile {
    param(
        [string] $VMName,
        [string] $SourcePath,
        [string] $DestinationPath,
        [pscredential] $Credential,
        [int] $Retries = 8,
        [int] $DelaySeconds = 3
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Copiaria para VM '$VMName': $SourcePath -> $DestinationPath"
        return
    }

    $svcName = Get-SandboxGuestServiceName -VMName $VMName
    if ($script:PROJETOVM_UseGuestServices -and $svcName) {
        Enable-VMIntegrationService -VMName $VMName -Name $svcName -ErrorAction SilentlyContinue
        $guestReady = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120
        if ($guestReady) {
            for ($i = 1; $i -le $Retries; $i++) {
                try {
                    Copy-VMFile -VMName $VMName -SourcePath $SourcePath -DestinationPath $DestinationPath -CreateFullPath -FileSource Host -ErrorAction Stop
                    return
                } catch {
                    if ($i -eq $Retries -and -not $Credential) { throw }
                    if ($i -lt $Retries) {
                        Write-LogWarning "Copy-VMFile falhou (tentativa $i/$Retries): $($_.Exception.Message). A tentar novamente em ${DelaySeconds}s..."
                        Start-Sleep -Seconds $DelaySeconds
                    }
                }
            }
        }
    }

    if (-not $Credential) {
        throw "N-o foi fornecida -Credential para c-pia via PowerShell Direct na VM '$VMName'."
    }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if ($i -eq 1 -and $script:SandboxGuestFileCopyMode -ne "psdirect") {
                $script:SandboxGuestFileCopyMode = "psdirect"
                if ($script:PROJETOVM_UseGuestServices) {
                    Write-LogHost "      Copy host->guest via PowerShell Direct (Guest Services indisponível nesta VM)."
                } else {
                    Write-LogHost "      Copy host->guest via PowerShell Direct (Guest Services desactivados por política de segurança)."
                }
            }
            Copy-SandboxVMFileToGuestViaPsDirect -VMName $VMName -Credential $Credential `
                -HostSourcePath $SourcePath -GuestDestinationPath $DestinationPath
            return
        } catch {
            if ($i -eq $Retries) { throw }
            Write-LogWarning "PowerShell Direct (host->guest) falhou (tentativa $i/$Retries): $($_.Exception.Message). Repetição em ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Update-SandboxCleanSnapshot {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][string] $SnapshotName
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Actualizaria snapshot '$SnapshotName' da VM '$VMName'."
        return
    }

    Stop-SandboxVM -VMName $VMName
    Start-Sleep -Milliseconds 500

    $existing = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-LogHost "        A remover snapshot anterior '$SnapshotName'..."
        Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName -ErrorAction Stop
    Write-LogHost "        Snapshot '$SnapshotName' actualizado com sucesso."
}

function Restore-SandboxSnapshot {
    param(
        [string] $VMName,
        [string] $SnapshotName
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Restauraria snapshot '$SnapshotName' da VM '$VMName'."
    } else {
        Restore-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false | Out-Null
    }
}

function Stop-SandboxVM {
    param(
        [string] $VMName
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Pararia a VM '$VMName'."
    } else {
        Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Test-SandboxGuestPathExists {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $GuestLiteralPath
    )
    try {
        $r = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            param($p)
            Test-Path -LiteralPath $p
        } -ArgumentList $GuestLiteralPath -ErrorAction Stop
        return [bool]$r
    } catch {
        return $false
    }
}

function Test-SandboxGuestAnalysisReportComplete {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [string] $ReportPath = "C:\analysis.txt",
        [string] $ReportEndMarker = "REPORT_END;"
    )
    try {
        $r = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            param($ReportPath, $ReportEndMarker)
            $result = [ordered]@{
                complete     = $false
                reportExists = $false
                reportBytes  = 0
                hasEndMarker = $false
            }
            if (-not (Test-Path -LiteralPath $ReportPath)) {
                return [pscustomobject]$result
            }

            $result.reportExists = $true
            $item = Get-Item -LiteralPath $ReportPath
            $result.reportBytes = [long]$item.Length
            if ($result.reportBytes -le 0) {
                return [pscustomobject]$result
            }

            $markerBytes = [System.Text.Encoding]::UTF8.GetBytes($ReportEndMarker)
            $scanBytes = [Math]::Max($markerBytes.Length, 8192)
            $fs = [System.IO.File]::Open($ReportPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $scan = [int][Math]::Min($scanBytes, $result.reportBytes)
                $null = $fs.Seek($result.reportBytes - $scan, [System.IO.SeekOrigin]::Begin)
                $buffer = New-Object byte[] $scan
                $read = $fs.Read($buffer, 0, $scan)
                if ($read -gt 0) {
                    $tail = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
                    if ($tail.Contains($ReportEndMarker)) {
                        $result.hasEndMarker = $true
                        $result.complete = $true
                    }
                }
            } finally {
                $fs.Dispose()
            }
            return [pscustomobject]$result
        } -ArgumentList $ReportPath, $ReportEndMarker -ErrorAction Stop
        return $r
    } catch {
        return [pscustomobject]@{
            complete     = $false
            reportExists = $false
            reportBytes  = 0
            hasEndMarker = $false
        }
    }
}

function Copy-SandboxGuestDiagnostics {
    <#
    .SYNOPSIS
        Copia artefatos de diagnostico do guest para a pasta do run no host (pulls parciais).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $HostDiagnosticsDir,
        [string] $GuestWorkDir = "C:\analysis_work"
    )

    if ([string]::IsNullOrWhiteSpace($HostDiagnosticsDir)) { return @() }

    $copied = New-Object System.Collections.Generic.List[string]
    $map = @(
        @{ guest = 'analysis_crash.log'; host = 'guest_analysis_crash.log' }
        @{ guest = 'analysis_launch.log'; host = 'guest_analysis_launch.log' }
        @{ guest = 'launch_error.txt'; host = 'guest_launch_error.txt' }
        @{ guest = 'sample_stderr.txt'; host = 'guest_sample_stderr.txt' }
    )

    foreach ($item in $map) {
        $guestPath = Join-Path $GuestWorkDir $item.guest
        $hostPath = Join-Path $HostDiagnosticsDir $item.host
        try {
            $exists = [bool](Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
                param($Path)
                Test-Path -LiteralPath $Path
            } -ArgumentList $guestPath -ErrorAction Stop)
            if (-not $exists) { continue }

            Copy-SandboxVMFileFromGuest -VMName $VMName -Credential $Credential `
                -GuestSourcePath $guestPath -HostDestinationPath $hostPath -Retries 2 -DelaySeconds 1
            if (Test-Path -LiteralPath $hostPath) {
                $copied.Add($item.host) | Out-Null
            }
        } catch { }
    }

    return @($copied)
}

function Try-ReceiveSandboxGuestReport {
    <#
    .SYNOPSIS
        Tenta obter o relatório do guest via PsDirect quando o pipe COM1 ainda não entregou.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $HostDestinationPath,
        [string] $GuestReportPath = "C:\analysis.txt",
        [string] $GuestDonePath = "C:\analysis_work\guest_analysis_done.txt",
        [string] $HostDiagnosticsDir = "",
        [string] $GuestWorkDir = "C:\analysis_work",
        [switch] $AllowPartial
    )

    $guestDone = $false
    try {
        $guestDone = [bool](Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            param($Path)
            Test-Path -LiteralPath $Path
        } -ArgumentList $GuestDonePath -ErrorAction Stop)
    } catch { }

    $reportStatus = Test-SandboxGuestAnalysisReportComplete -VMName $VMName -Credential $Credential -ReportPath $GuestReportPath
    $shouldPull = $false
    $reason = ""

    if ($guestDone) {
        $shouldPull = $true
        $reason = "guest_analysis_done.txt"
    } elseif ($reportStatus.complete) {
        $shouldPull = $true
        $reason = "REPORT_END; em C:\analysis.txt"
    } elseif ($AllowPartial -and $reportStatus.reportExists -and $reportStatus.reportBytes -gt 200) {
        $shouldPull = $true
        $reason = "relatório parcial ($($reportStatus.reportBytes) bytes, guest inativo)"
    }

    if (-not $shouldPull) {
        return @{ pulled = $false; reason = ""; guestDone = $guestDone; reportStatus = $reportStatus; diagnosticsCopied = @() }
    }

    Copy-SandboxVMFileFromGuest -VMName $VMName -Credential $Credential `
        -GuestSourcePath $GuestReportPath -HostDestinationPath $HostDestinationPath -Retries 3 -DelaySeconds 2

    $pulled = Test-Path -LiteralPath $HostDestinationPath
    $diagCopied = @()
    if ($pulled -and $AllowPartial -and -not [string]::IsNullOrWhiteSpace($HostDiagnosticsDir)) {
        $diagCopied = Copy-SandboxGuestDiagnostics -VMName $VMName -Credential $Credential `
            -HostDiagnosticsDir $HostDiagnosticsDir -GuestWorkDir $GuestWorkDir
    }

    return @{
        pulled            = $pulled
        reason            = if ($pulled) { $reason } else { "" }
        guestDone         = $guestDone
        reportStatus      = $reportStatus
        partial           = (-not $reportStatus.complete) -and $AllowPartial
        diagnosticsCopied = $diagCopied
    }
}

function Get-SandboxGuestFileCopyMode {
    if ($script:SandboxGuestFileCopyMode) { return $script:SandboxGuestFileCopyMode }

    try {
        Import-Module Hyper-V -ErrorAction SilentlyContinue | Out-Null
        $names = [enum]::GetNames([Microsoft.HyperV.PowerShell.CopyFileSourceType])
        if ($names -contains 'Guest') {
            $script:SandboxGuestFileCopyMode = 'CmdletGuest'
        } else {
            $script:SandboxGuestFileCopyMode = 'PsDirect'
        }
    } catch {
        $script:SandboxGuestFileCopyMode = 'PsDirect'
    }

    return $script:SandboxGuestFileCopyMode
}

function Copy-SandboxVMFileFromGuestViaPsDirect {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $GuestSourcePath,
        [Parameter(Mandatory = $true)][string] $HostDestinationPath
    )

    $chunkSize = Get-SandboxPsDirectChunkSize
    $offset = 0
    $parent = Split-Path -Parent -Path $HostDestinationPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $HostDestinationPath) {
        Remove-Item -LiteralPath $HostDestinationPath -Force -ErrorAction SilentlyContinue
    }

    $fs = [System.IO.File]::Open($HostDestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        while ($true) {
            $chunk = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
                param($Path, $Offset, $Size)
                if (-not (Test-Path -LiteralPath $Path)) {
                    throw "Ficheiro guest não encontrado: $Path"
                }

                $fsIn = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $null = $fsIn.Seek($Offset, [System.IO.SeekOrigin]::Begin)
                    $buffer = New-Object byte[] $Size
                    $read = $fsIn.Read($buffer, 0, $Size)
                    if ($read -le 0) {
                        return @{ eof = $true; data = $null }
                    }

                    if ($read -lt $Size) {
                        $trim = New-Object byte[] $read
                        [Array]::Copy($buffer, 0, $trim, 0, $read)
                        $buffer = $trim
                    }

                    return @{
                        eof = ($read -lt $Size)
                        data = [Convert]::ToBase64String($buffer)
                    }
                } finally {
                    $fsIn.Dispose()
                }
            } -ArgumentList $GuestSourcePath, $offset, $chunkSize -ErrorAction Stop

            if ($chunk.data) {
                $bytes = [Convert]::FromBase64String([string]$chunk.data)
                if ($bytes.Length -gt 0) {
                    $fs.Write($bytes, 0, $bytes.Length)
                }
                $offset += $bytes.Length
            }

            if ($chunk.eof) { break }
        }
    } finally {
        $fs.Dispose()
    }
}

function Copy-SandboxVMFileFromGuest {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $GuestSourcePath,
        [Parameter(Mandatory = $true)][string] $HostDestinationPath,
        [int] $Retries = 12,
        [int] $DelaySeconds = 4
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Copiaria da VM '${VMName}': ${GuestSourcePath} -> ${HostDestinationPath}"
        return
    }

    $copyMode = Get-SandboxGuestFileCopyMode
    if ($copyMode -eq 'PsDirect') {
        for ($i = 1; $i -le $Retries; $i++) {
            try {
                if ($i -eq 1) {
                    Write-LogHost "      Copy guest->host via PowerShell Direct (Copy-VMFile Guest indisponível neste Hyper-V)."
                }
                Copy-SandboxVMFileFromGuestViaPsDirect -VMName $VMName -Credential $Credential `
                    -GuestSourcePath $GuestSourcePath -HostDestinationPath $HostDestinationPath
                return
            } catch {
                if ($i -eq $Retries) { throw }
                Write-LogWarning "PowerShell Direct (guest->host) falhou (tentativa $i/$Retries): $($_.Exception.Message). Repetição em ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
        return
    }

    $svcName = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $svcName) {
        throw "Guest Services não disponível na VM '${VMName}'."
    }
    Enable-VMIntegrationService -VMName $VMName -Name $svcName -ErrorAction SilentlyContinue
    $null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120

    $parent = Split-Path -Parent -Path $HostDestinationPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    if (Test-Path -LiteralPath $HostDestinationPath) {
        Remove-Item -LiteralPath $HostDestinationPath -Force -ErrorAction SilentlyContinue
    }

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Copy-VMFile -VMName $VMName -SourcePath $GuestSourcePath -DestinationPath $HostDestinationPath -CreateFullPath -FileSource Guest -ErrorAction Stop
            return
        } catch {
            if ($i -eq $Retries) { throw }
            Write-LogWarning "Copy-VMFile (guest->host) falhou (tentativa $i/$Retries): $($_.Exception.Message). Repetição em ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}
