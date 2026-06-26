# --- Módulo: Phase8-Install.ps1 ---
# --- Instalação automática do Windows na VM ---

Write-Host "[8/8] Instalação do Windows..."

$snap = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue

# --- Verificação de snapshot ou modo manual ---
if ($snap) {
    Write-Host "      Snapshot '$SnapshotName' ja existe. Nada a fazer."

} elseif (-not $AutoInstall) {
    Write-Host "      AutoInstallWindows=false. Instale manualmente e crie o snapshot:"
    Write-Host "        Stop-VM -Name $VMName -Force"
    Write-Host "        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName"

} else {
    Log "Início da instalação automática do Windows na VM '$VMName' (Gen$VMGeneration)."

    $vmState = (Get-VM -Name $VMName).State
    if ($vmState -ne "Off") {
        Stop-VM -Name $VMName -TurnOff -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 5
    }

    # --- Preparação do autounattend.xml ---
    Log "A preparar autounattend.xml..."
    $unattendDir = Join-Path $VMPath "unattend"
    Ensure-DirectoryExists -Path $unattendDir
    $unattendXml = Join-Path $unattendDir "autounattend.xml"

    # Phase8 é dot-sourced: $PSScriptRoot = ...\Setup; o autounattend custom vive na pasta pai
    $customUnattendName = "autounattend-malware-behavior-detection-user-gen1.xml"
    $customUnattendCandidates = @(
        (Join-Path (Split-Path -Parent $PSScriptRoot) $customUnattendName),
        (Join-Path $PSScriptRoot $customUnattendName)
    )
    $customUnattendPath = $customUnattendCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $customUnattendPath) { $customUnattendPath = $customUnattendCandidates[0] }
    $usedSource = $null

    # --- Escolha da fonte do autounattend (custom Gen1 vs gerado) ---
    if ($VMGeneration -eq 1 -and (Test-Path -LiteralPath $customUnattendPath)) {
        Copy-Item -Path $customUnattendPath -Destination $unattendXml -Force -ErrorAction Stop
        $usedSource = "custom-file"
        Log "autounattend.xml usado: $customUnattendPath (Gen1)."
    } else {
        if ($VMGeneration -ne 1) {
            Log "AVISO: VMGeneration=$VMGeneration. O ficheiro customizado é Gen1; usar autounattend 'oficial' gerado." "WARN"
        } elseif (-not (Test-Path -LiteralPath $customUnattendPath)) {
            Log "AVISO: ficheiro customizado não encontrado: $customUnattendPath. Usar autounattend 'oficial' gerado." "WARN"
        }

        $xml = New-Windows10UnattendXml -ComputerName $VMName -UserName $GuestUser -Password $GuestPassword -VMGeneration $VMGeneration
        $xml | Set-Content -Path $unattendXml -Encoding UTF8
        $usedSource = "official-generated"
        Log "autounattend.xml 'oficial' gerado (source: New-Windows10UnattendXml)."
    }

    if (-not (Test-Path -LiteralPath $unattendXml)) {
        throw "autounattend.xml não foi criado em '$unattendXml'. Abortando."
    }

    # --- Aplicação de credenciais guest ao autounattend ---
    # valores de _Config/WPF têm de coincidir com a conta criada na VM
    try {
        Set-UnattendGuestCredentialsInPlace `
            -UnattendXmlPath $unattendXml `
            -UserName $GuestUser `
            -Password $GuestPassword `
            -DisplayName "Malware Analyst" `
            -ComputerName $VMName
        Log "Credenciais guest aplicadas ao autounattend.xml (user='$GuestUser')."
    } catch {
        throw "Falha ao aplicar credenciais guest ao autounattend.xml: $($_.Exception.Message)"
    }

    # --- Normalização de idioma/locale conforme o ISO ---
    try {
        if ($isoLang) {
            Set-UnattendLanguageInPlace -UnattendXmlPath $unattendXml -UiLanguage $isoLang
            Log "Idioma aplicado ao autounattend.xml: $isoLang"
        }
    } catch {
        Log "AVISO: Não foi possível ajustar idioma no autounattend.xml: $($_.Exception.Message)" "WARN"
    }

    # --- Remoção de international settings (apenas autounattend gerado) ---
    # no custom Gen1 manter International-Core-WinPE para Setup silencioso
    if ($usedSource -eq "official-generated") {
        try {
            Remove-UnattendInternationalSettings -UnattendXmlPath $unattendXml
            Log "International settings removidas do autounattend gerado (compat. ISO / idioma)."
        } catch {
            Log "AVISO: Não foi possível remover international settings do autounattend.xml: $($_.Exception.Message)" "WARN"
        }
    } else {
        Log "Mantendo Microsoft-Windows-International-Core-WinPE no autounattend custom (Gen1 / en-US)."
    }

    Log "autounattend.xml pronto (source: $usedSource)."

    # --- Hash SHA256 para correlacionar a execução ---
    try {
        $unattendHash = (Get-FileHash -Path $unattendXml -Algorithm SHA256).Hash
        Log "autounattend.xml SHA256: $unattendHash"
    } catch {
        Log "AVISO: não foi possível calcular SHA256 do autounattend.xml: $($_.Exception.Message)" "WARN"
    }

    if ($VMGeneration -eq 1) {
        # --- Gen1: injeção de autounattend no ISO via oscdimg ---

        $isoWithUnattend = Join-Path $VMPath "Windows_unattend.iso"

        Log "A criar ISO com autounattend.xml injetado (Gen1)..."
        Write-Host "      A criar ISO com autounattend.xml (pode demorar 2-5 min)..."
        try {
            New-WindowsIsoWithUnattend `
                -SourceIsoPath $WindowsIsoPath `
                -UnattendXmlPath $unattendXml `
                -OutputIsoPath $isoWithUnattend
            Log "ISO com autounattend criado: $isoWithUnattend"
            Write-Host "      ISO criado: $isoWithUnattend"
            $isoToUse = $isoWithUnattend
        } catch {
            Log "AVISO: Não foi possível criar ISO com autounattend: $($_.Exception.Message). A usar ISO original (instalação manual necessária)." "WARN"
            Write-Warning "      Não foi possível criar ISO com autounattend: $($_.Exception.Message)"
            Write-Warning "      A usar ISO original -- instalação precisara de intervencao manual."
            Write-Warning "      Instale o Windows ADK de: https://go.microsoft.com/fwlink/?linkid=2196127"
            $isoToUse = $WindowsIsoPath
        }

        # --- DVD IDE com ISO (custom ou original como fallback) ---
        Log "A configurar DVD drive IDE (Gen1) com: $isoToUse"
        try { Set-VMDvdDrive -VMName $VMName -Path $isoToUse -ErrorAction Stop | Out-Null } catch {
            try { Add-VMDvdDrive -VMName $VMName -Path $isoToUse -ErrorAction Stop | Out-Null } catch { }
        }
        $dvd = Get-VMDvdDrive -VMName $VMName | Select-Object -First 1
        if (-not $dvd -or [string]::IsNullOrWhiteSpace($dvd.Path)) {
            throw "DVD drive não configurado em Gen1."
        }
        Log "DVD -> $($dvd.Path)"
        Write-Host "      DVD: $($dvd.ControllerType)($($dvd.ControllerNumber),$($dvd.ControllerLocation)) -> $($dvd.Path)"

        # --- Ordem de boot Gen1: CD primeiro ---
        $bios = Get-VMBios -VMName $VMName -ErrorAction SilentlyContinue
        if ($bios) {
            Set-VMBios -VMName $VMName -StartupOrder @("CD", "IDE", "LegacyNetworkAdapter", "Floppy") | Out-Null
            Log "BIOS boot order: CD primeiro."
            Write-Host "      BIOS boot order: CD primeiro."
        }

    } else {
        # --- Gen2: autounattend em partição FAT32 + DVD SCSI ---

        Log "A injetar autounattend.xml no Sandbox.vhdx (particao FAT32, Gen2)..."
        $unattendInjected = $false
        try {
            $disk    = Mount-VHD -Path $VHDPath -PassThru -ErrorAction Stop
            $diskNum = $disk.DiskNumber
            try {
                Initialize-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction SilentlyContinue | Out-Null
                $existingFat = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue |
                               Where-Object { $_.Size -lt 600MB -and $_.Type -eq "Basic" } |
                               Select-Object -First 1
                if ($existingFat) {
                    $dl = $existingFat.DriveLetter
                    if (-not $dl -or $dl -eq [char]0) {
                        Add-PartitionAccessPath -DiskNumber $diskNum -PartitionNumber $existingFat.PartitionNumber -AssignDriveLetter -ErrorAction SilentlyContinue | Out-Null
                        Start-Sleep -Milliseconds 500
                        $dl = (Get-Partition -DiskNumber $diskNum -PartitionNumber $existingFat.PartitionNumber).DriveLetter
                    }
                } else {
                    # cria partição FAT32 de 256 MB para o Windows Setup encontrar autounattend.xml
                    $part = New-Partition -DiskNumber $diskNum -Size 256MB -AssignDriveLetter -ErrorAction Stop
                    Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel "UNATTEND" -Confirm:$false -ErrorAction Stop | Out-Null
                    $dl = $null
                    for ($i = 0; $i -lt 20; $i++) {
                        $dl = (Get-Partition -DiskNumber $diskNum -PartitionNumber $part.PartitionNumber -ErrorAction SilentlyContinue).DriveLetter
                        if ($dl -and $dl -ne [char]0) { break }
                        Start-Sleep -Milliseconds 300
                    }
                }
                if (-not $dl -or $dl -eq [char]0) { throw "Sem letra de drive para a particao FAT32." }
                Copy-Item -Path $unattendXml -Destination "${dl}:\autounattend.xml" -Force -ErrorAction Stop
                Log "autounattend.xml copiado para ${dl}:\autounattend.xml"
                Write-Host "      autounattend.xml injetado no Sandbox.vhdx (${dl}:)."
                $unattendInjected = $true
            } finally {
                Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {
            Log "AVISO: Não foi possível injetar autounattend.xml: $($_.Exception.Message)" "WARN"
            Write-Warning "      autounattend.xml não injetado."
        }

        # --- DVD em SCSI (0,1) ---
        Log "A configurar DVD drive SCSI (Gen2)..."
        $existingDvds = @(Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue)
        foreach ($d in $existingDvds) {
            try { Remove-VMDvdDrive -VMName $VMName -ControllerNumber $d.ControllerNumber -ControllerLocation $d.ControllerLocation -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
        try { Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1 -ErrorAction SilentlyContinue | Out-Null } catch { }
        Add-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 -Path $WindowsIsoPath -ErrorAction Stop | Out-Null
        $dvd = Get-VMDvdDrive -VMName $VMName | Where-Object { $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq 1 } | Select-Object -First 1
        if (-not $dvd -or [string]::IsNullOrWhiteSpace($dvd.Path)) {
            throw "DVD drive não criado em SCSI(0,1)."
        }
        Log "DVD SCSI(0,1) -> $($dvd.Path)"
        Write-Host "      DVD: SCSI(0,1) -> $WindowsIsoPath"

        # --- Remoção de HDD extras em slots > 0 ---
        $extraHdds = @(Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.ControllerLocation -gt 0 })
        foreach ($ex in $extraHdds) {
            try { Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber $ex.ControllerNumber -ControllerLocation $ex.ControllerLocation -ErrorAction SilentlyContinue | Out-Null } catch { }
        }

        # --- Ordem de boot Gen2: DVD SCSI primeiro ---
        $dvdObj = Get-VMDvdDrive -VMName $VMName | Where-Object { $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq 1 } | Select-Object -First 1
        Set-VMFirmware -VMName $VMName -FirstBootDevice $dvdObj | Out-Null
        Log "FirstBootDevice definido para DVD SCSI(0,1)."
    }

    # --- Resumo da configuração final ---
    $dvdInfo  = Get-VMDvdDrive -VMName $VMName | Select-Object -First 1
    $hddInfo  = Get-VMHardDiskDrive -VMName $VMName | Select-Object -First 1
    Write-Host ""
    Write-Host "      Configuração final da VM:"
    Write-Host "        Generation : Gen$VMGeneration"
    if ($VMGeneration -eq 2) {
        $fw = Get-VMFirmware -VMName $VMName
        Write-Host "        SecureBoot : $($fw.SecureBoot)"
    }
    Write-Host "        DVD        : $($dvdInfo.ControllerType)($($dvdInfo.ControllerNumber),$($dvdInfo.ControllerLocation)) -> $($dvdInfo.Path)"
    Write-Host "        HDD        : $($hddInfo.ControllerType)($($hddInfo.ControllerNumber),$($hddInfo.ControllerLocation)) -> $($hddInfo.Path)"
    Write-Host ""

    # --- Arranque da VM e espera por PowerShell Direct ---
    Write-Host "      A arrancar VM (instalação pode demorar 15-40 min)..."
    $dvdBootPath = $null
    try {
        $dvdBootPath = (Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    } catch { }
    if ([string]::IsNullOrWhiteSpace($dvdBootPath)) { $dvdBootPath = $WindowsIsoPath }
    Log "VM '$VMName' a arrancar (DVD ISO: $dvdBootPath)."
    Start-VM -Name $VMName | Out-Null

    # PS Direct é mais fiável que Heartbeat; falha até o logon guest estar disponível
    $secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
    $cred = [pscredential]::new($GuestUser, $secure)
    $ok = Wait-VMPowerShellDirectReady -VMName $VMName -Credential $cred -TimeoutSeconds 0 -LogPath $LogFile -LogIntervalSeconds 10

    if (-not $ok) {
        # --- Fallback de diagnóstico via Heartbeat ---
        $hbOk = $false
        try { $hbOk = Wait-VMHeartbeatOk -VMName $VMName -TimeoutSeconds 120 -LogPath $LogFile -LogIntervalSeconds 5 } catch { }

        Write-Warning "      PowerShell Direct ainda não ficou OK."
        if ($hbOk) { Write-Warning "      Nota: Heartbeat ficou OK, mas o guest ainda não aceitou logon (PS Direct)." }
        Log "PowerShell Direct timeout. VM continua ligada." "WARN"
        Write-Host ""
        Write-Host "      Quando a instalação terminar, execute:"
        Write-Host "        Stop-VM -Name $VMName -Force"
        Write-Host "        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName"
    } else {
        Log "PowerShell Direct OK. A criar snapshot '$SnapshotName'..."
        if ($unattendHash) {
            Log "Correlacao: autounattend.xml SHA256 usado nesta execucao (Gen$VMGeneration): $unattendHash"
        }
        Write-Host "      Instalação concluida. A parar a VM para criar snapshot..."
        try {
            Stop-VM -Name $VMName -Force -ErrorAction Stop | Out-Null
        } catch {
            Log "AVISO ao parar VM antes do snapshot: $($_.Exception.Message)" "WARN"
            try { Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
        }

        # Hyper-V exige VM totalmente Off antes de Checkpoint-VM
        $waitOffDeadline = (Get-Date).AddMinutes(8)
        while ((Get-Date) -lt $waitOffDeadline) {
            $st = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
            if ($st -eq 'Off') { break }
            Start-Sleep -Seconds 2
        }
        $finalState = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
        if ($finalState -ne 'Off') {
            Log "AVISO: VM '$VMName' estado='$finalState' (esperado Off antes do checkpoint)." "WARN"
        }
        Start-Sleep -Seconds 6

        # --- Criação do snapshot com retentativas ---
        Write-Host "      A criar snapshot '$SnapshotName'..."
        $snapErr = $null
        for ($ti = 1; $ti -le 12; $ti++) {
            try {
                Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName -ErrorAction Stop
                $snapErr = $null
                break
            } catch {
                $snapErr = $_
                Log "Checkpoint-VM tentativa $ti/12 falhou: $($_.Exception.Message)" "WARN"
                Start-Sleep -Seconds 8
            }
        }
        if ($snapErr) {
            throw "Não foi possível criar o snapshot '$SnapshotName' apos varias tentativas: $($snapErr.Exception.Message)"
        }
        Write-Host "      Snapshot '$SnapshotName' criado."
        Log "Snapshot '$SnapshotName' criado com sucesso."
    }
}
