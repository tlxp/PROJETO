function Copy-SandboxVMFile {
    param(
        [string] $VMName,
        [string] $SourcePath,
        [string] $DestinationPath,
        [int] $Retries = 8,
        [int] $DelaySeconds = 3
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Copiaria para VM '$VMName': $SourcePath -> $DestinationPath"
        return
    }

    $svcName = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $svcName) {
        throw "Guest Services n-o dispon-vel na VM '$VMName'. N-o - poss-vel usar Copy-VMFile. Instale/arranque o Windows na VM e garanta que o Integration Service 'Guest Services' existe/est- dispon-vel."
    }

    Enable-VMIntegrationService -VMName $VMName -Name $svcName -ErrorAction SilentlyContinue
    $null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Copy-VMFile -VMName $VMName -SourcePath $SourcePath -DestinationPath $DestinationPath -CreateFullPath -FileSource Host -ErrorAction Stop
            return
        } catch {
            if ($i -eq $Retries) { throw }
            Write-LogWarning "Copy-VMFile falhou (tentativa $i/$Retries): $($_.Exception.Message). A tentar novamente em ${DelaySeconds}s..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
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

    $chunkSize = 524288
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
