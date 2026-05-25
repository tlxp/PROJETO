param(
    [switch] $DryRun
)

$script:SandboxGuestFileCopyMode = $null

function Get-LogTimestamp {
    return Get-Date -Format "HH:mm:ss"
}

function Write-LogHost {
    param([string] $Message)
    $t = Get-LogTimestamp
    Write-Host "[$t] $Message"
}

function Write-LogWarning {
    param([string] $Message)
    $t = Get-LogTimestamp
    Write-Warning "[$t] $Message"
}

function Write-SandboxLog {
    param(
        [string] $Message,
        [string] $LogPath,
        [ValidateSet("INFO","WARN","ERROR")]
        [string] $Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Write-SandboxJsonLog {
    param(
        [hashtable] $Data,
        [string] $JsonPath
    )
    if (-not $JsonPath) { return }
    try {
        $json = $Data | ConvertTo-Json -Depth 6
        $json | Set-Content -Path $JsonPath -Encoding UTF8
    } catch { }
}

function Assert-FileSha1 {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha1,
        [string] $Label = "ficheiro"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "O $Label n-o foi encontrado em: $Path"
    }

    $expected = ($ExpectedSha1 -replace '\s', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "SHA-1 esperado vazio para o $Label (config inv-lida)."
    }

    $actual = $null
    try {
        $h = Get-FileHash -LiteralPath $Path -Algorithm SHA1 -ErrorAction Stop
        $actual = ($h.Hash -replace '\s', '').ToLowerInvariant()
    } catch {
        throw "Falha ao calcular SHA-1 do $Label em '$Path': $($_.Exception.Message)"
    }

    if ($actual -ne $expected) {
        throw "SHA-1 do $Label N-O coincide. Esperado: $expected | Atual: $actual | Ficheiro: $Path"
    }

    # Devolver o hash calculado para diagn-stico/logs
    return $actual
}

function Get-WindowsIsoInstallMediaCandidates {
    param([Parameter(Mandatory = $true)][string] $IsoRoot)
    return @(
        (Join-Path $IsoRoot 'x64\sources\install.wim'),
        (Join-Path $IsoRoot 'x64\sources\install.esd'),
        (Join-Path $IsoRoot 'sources\install.wim'),
        (Join-Path $IsoRoot 'sources\install.esd'),
        (Join-Path $IsoRoot 'x86\sources\install.wim'),
        (Join-Path $IsoRoot 'x86\sources\install.esd')
    )
}

function Get-WindowsImageLanguagesFromInstallMedia {
    <#
    .SYNOPSIS
        Lista idiomas expostos pelo install.wim / install.esd (indice 1) via Get-WindowsImage.
        Fallback quando lang.ini nao existe ou nao tem [Available UI Languages] reconhecivel.
    #>
    param([Parameter(Mandatory = $true)][string] $IsoRoot)

    foreach ($media in (Get-WindowsIsoInstallMediaCandidates -IsoRoot $IsoRoot)) {
        if (-not (Test-Path -LiteralPath $media)) { continue }
        try {
            $img = Get-WindowsImage -ImagePath $media -Index 1 -ErrorAction Stop
            if (-not $img.Languages) { continue }
            # Get-WindowsImage pode devolver Languages como string "en-US". Se passar pelo pipeline,
            # o PowerShell enumera CARACTERES — o primeiro "idioma" vira "e" e corrompe o autounattend.
            $langList = @()
            if ($img.Languages -is [string]) {
                $t = $img.Languages.Trim()
                if ($t) { $langList = @($t) }
            } else {
                $langList = @($img.Languages | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
            }
            if ($langList.Count -gt 0) { return $langList }
        } catch {
            continue
        }
    }
    return @()
}

function Get-WindowsIsoUiLanguages {
    <#
    .SYNOPSIS
        Devolve os idiomas de UI disponíveis no ISO (sources\lang.ini), se possível.
    .DESCRIPTION
        - Monta o ISO temporariamente e lê a secção [Available UI Languages] de lang.ini.
        - Procura em sources\lang.ini na raiz do volume **e** em x64\sources\lang.ini / x86\sources\lang.ini
          (estrutura típica de ISOs MCT / imagens só x64).
        - Se lang.ini nao listar idiomas, tenta **install.wim / install.esd** com Get-WindowsImage (indice 1).
        - Se falhar, devolve lista vazia (o chamador decide fallback).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $IsoPath
    )

    $langs = @()
    if (-not (Test-Path -LiteralPath $IsoPath)) { return $langs }

    $mounted = $false
    try {
        Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -ErrorAction Stop | Out-Null
        $mounted = $true
        Start-Sleep -Milliseconds 1200

        $vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume | Select-Object -First 1
        $isoDrive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $null }
        if (-not $isoDrive) { return $langs }

        $langIniCandidates = @(
            (Join-Path $isoDrive "sources\lang.ini"),
            (Join-Path $isoDrive "x64\sources\lang.ini"),
            (Join-Path $isoDrive "x86\sources\lang.ini")
        )

        foreach ($langIni in $langIniCandidates) {
            if (-not (Test-Path -LiteralPath $langIni)) { continue }
            try {
                $content = Get-Content -LiteralPath $langIni -ErrorAction Stop
            } catch {
                continue
            }
            $inSection = $false
            foreach ($line in $content) {
                $t = ("" + $line).Trim()
                if ($t -match '^\[(.+)\]\s*$') {
                    $sec = $matches[1].Trim()
                    $inSection = ($sec -match '^(?i)available ui languages$')
                    continue
                }
                if (-not $inSection) { continue }
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                # Linha so com tag (en-US) ou chave=valor (en-US = 1 / en-US=true)
                if ($t -match '^\s*([a-zA-Z]{2}-[a-zA-Z]{2,})\s*(=.*)?$') {
                    $langs += $matches[1]
                }
            }
        }

        if (@($langs).Count -eq 0) {
            foreach ($wl in (Get-WindowsImageLanguagesFromInstallMedia -IsoRoot $isoDrive)) {
                $langs += $wl
            }
        }

        $langs = $langs | Sort-Object -Unique
        return $langs
    }
    catch {
        return @()
    }
    finally {
        if ($mounted) {
            try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
    }
}

function New-IsoFromFolder {
    <#
    .SYNOPSIS
        Cria um ISO bootavel a partir de uma pasta usando oscdimg.exe (Windows ADK)
        ou, como fallback, copia os ficheiros para um ISO existente via robocopy+oscdimg.
        Usado para injetar autounattend.xml num ISO do Windows.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $SourceFolder,
        [Parameter(Mandatory = $true)][string] $IsoPath,
        [string] $VolumeLabel = "UNATTEND"
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Criaria ISO: $IsoPath a partir de $SourceFolder"
        return
    }
    if (-not (Test-Path $SourceFolder)) { throw "Pasta nao existe: $SourceFolder" }
    $parent = Split-Path -Parent $IsoPath
    if ($parent) { Ensure-DirectoryExists -Path $parent }
    throw "New-IsoFromFolder: use New-WindowsIsoWithUnattend para criar ISOs bootaveis."
}

function New-WindowsIsoWithUnattend {
    <#
    .SYNOPSIS
        Cria um novo ISO do Windows com autounattend.xml injetado de duas formas:
        1. Na raiz do ISO (para WinPE que arranque via boot.wim)
        2. Dentro do boot.wim (index 2 = WinPE) em \Windows\System32\
           O WinPE procura autounattend.xml em \Windows\System32\ quando nao
           encontra na raiz -- isto garante automacao mesmo em ISOs MCT.
        Requer: oscdimg.exe (Windows ADK) e dism.exe (built-in no Windows).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $SourceIsoPath,
        [Parameter(Mandatory = $true)][string] $UnattendXmlPath,
        [Parameter(Mandatory = $true)][string] $OutputIsoPath,
        [string] $OscdimgPath = ""
    )

    if (-not (Test-Path -LiteralPath $SourceIsoPath)) { throw "ISO nao encontrado: $SourceIsoPath" }
    if (-not (Test-Path -LiteralPath $UnattendXmlPath)) { throw "autounattend.xml nao encontrado: $UnattendXmlPath" }

    # Encontrar oscdimg.exe
    if ([string]::IsNullOrWhiteSpace($OscdimgPath) -or -not (Test-Path $OscdimgPath)) {
        $candidates = @(
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
            "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        )
        foreach ($c in $candidates) { if (Test-Path $c) { $OscdimgPath = $c; break } }
    }
    if ([string]::IsNullOrWhiteSpace($OscdimgPath) -or -not (Test-Path $OscdimgPath)) {
        throw "oscdimg.exe nao encontrado. Instale o Windows ADK (Deployment Tools): https://go.microsoft.com/fwlink/?linkid=2196127"
    }
    Write-LogHost "oscdimg.exe: $OscdimgPath"

    $tmpDir  = Join-Path $env:TEMP ("WinISO_" + [System.Guid]::NewGuid().ToString("N"))
    $wimDir  = Join-Path $env:TEMP ("WimMount_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    New-Item -ItemType Directory -Path $wimDir  -Force | Out-Null

    try {
        # 1. Montar ISO e copiar conteudo
        Write-LogHost "A montar ISO: $SourceIsoPath"
        Mount-DiskImage -ImagePath $SourceIsoPath -StorageType ISO -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 800
        $vol = Get-DiskImage -ImagePath $SourceIsoPath | Get-Volume | Select-Object -First 1
        $isoDrive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $null }
        if (-not $isoDrive) { throw "ISO montado mas sem letra de drive." }

        Write-LogHost "A copiar ISO para $tmpDir (pode demorar 2-3 min)..."
        robocopy $isoDrive $tmpDir /E /NFL /NDL /NJH /NJS | Out-Null

        Dismount-DiskImage -ImagePath $SourceIsoPath -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 400

        # 2. Colocar autounattend.xml na raiz do ISO (metodo classico)
        Copy-Item -Path $UnattendXmlPath -Destination (Join-Path $tmpDir "autounattend.xml") -Force
        Write-LogHost "autounattend.xml copiado para raiz do ISO."

        # 3. Injetar autounattend.xml dentro do boot.wim (WinPE)
        #    O WinPE (index 2 do boot.wim) procura autounattend.xml em:
        #    - raiz de qualquer drive (A:, B:, C:, D:, etc.)
        #    - \Windows\System32\ no WinPE (X:\Windows\System32\)
        #    Injetamos em \Windows\System32\ para garantia maxima.
        $bootWimSrc = Join-Path $tmpDir "sources\boot.wim"
        if (Test-Path $bootWimSrc) {
            Write-LogHost "A injetar autounattend.xml no boot.wim (WinPE)..."
            try {
                # boot.wim pode ser read-only (vem do ISO) -- remover atributo
                Set-ItemProperty -Path $bootWimSrc -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

                # Montar index 2 (WinPE Setup -- index 1 e o Setup loader, index 2 e o WinPE completo)
                # Tentar index 2 primeiro, fallback para index 1
                $wimIndex = 2
                $dismResult = & dism /Mount-Wim /WimFile:"$bootWimSrc" /index:$wimIndex /MountDir:"$wimDir" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $wimIndex = 1
                    $dismResult = & dism /Mount-Wim /WimFile:"$bootWimSrc" /index:$wimIndex /MountDir:"$wimDir" 2>&1
                }

                if ($LASTEXITCODE -eq 0) {
                    # Copiar autounattend.xml para System32 do WinPE
                    $sys32 = Join-Path $wimDir "Windows\System32"
                    if (Test-Path $sys32) {
                        Copy-Item -Path $UnattendXmlPath -Destination (Join-Path $sys32 "autounattend.xml") -Force
                        Write-LogHost "autounattend.xml injetado em WinPE\Windows\System32\ (index $wimIndex)."
                    }
                    # Desmontar e guardar
                    & dism /Unmount-Wim /MountDir:"$wimDir" /Commit 2>&1 | Out-Null
                    Write-LogHost "boot.wim atualizado com sucesso."
                } else {
                    Write-LogHost "AVISO: Nao foi possivel montar boot.wim via DISM. A continuar sem injecao no WIM."
                    try { & dism /Unmount-Wim /MountDir:"$wimDir" /Discard 2>&1 | Out-Null } catch { }
                }
            } catch {
                Write-LogHost "AVISO: Erro ao injetar no boot.wim: $($_.Exception.Message)"
                try { & dism /Unmount-Wim /MountDir:"$wimDir" /Discard 2>&1 | Out-Null } catch { }
            }
        }

        # 4. Criar ISO bootavel com oscdimg
        $bootSector = Join-Path $tmpDir "boot\etfsboot.com"
        $efiBoot    = Join-Path $tmpDir "efi\microsoft\boot\efisys.bin"

        if (Test-Path $bootSector) {
            if (Test-Path $efiBoot) {
                $bootArg = "-bootdata:2#p0,e,b`"$bootSector`"#pEF,e,b`"$efiBoot`""
            } else {
                $bootArg = "-b`"$bootSector`""
            }
        } else { $bootArg = "" }

        if (Test-Path $OutputIsoPath) { Remove-Item -LiteralPath $OutputIsoPath -Force -ErrorAction SilentlyContinue }

        $argList = "-m -o -u2 -udfver102"
        if ($bootArg) { $argList += " $bootArg" }
        $argList += " `"$tmpDir`" `"$OutputIsoPath`""

        Write-LogHost "A criar ISO final: $OutputIsoPath"
        $proc = Start-Process -FilePath $OscdimgPath -ArgumentList $argList -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) { throw "oscdimg falhou (exit $($proc.ExitCode))." }

        $sizeMB = [Math]::Round((Get-Item $OutputIsoPath).Length / 1MB, 0)
        Write-LogHost "ISO criado: $OutputIsoPath ($sizeMB MB)"

    } finally {
        try { Dismount-DiskImage -ImagePath $SourceIsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        try { & dism /Unmount-Wim /MountDir:"$wimDir" /Discard 2>&1 | Out-Null } catch { }
        try { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        try { Remove-Item -LiteralPath $wimDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function New-UnattendVhdx {
    <#
    .SYNOPSIS
        Cria um pequeno VHDX com um volume e copia ficheiros (ex.: autounattend.xml) para a raiz.
    .DESCRIPTION
        Este VHDX pode ser anexado - VM como disco adicional; o Windows Setup procura autounattend.xml
        em volumes adicionais, por isso funciona como alternativa a um ISO de USB.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $SourceFolder,
        [Parameter(Mandatory = $true)][string] $VhdxPath,
        [int] $SizeMB = 512
    )
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Criaria VHDX: $VhdxPath a partir de $SourceFolder"
        return
    }
    if (-not (Test-Path $SourceFolder)) { throw "Pasta n-o existe: $SourceFolder" }
    $parent = Split-Path -Parent $VhdxPath
    if ($parent) { Ensure-DirectoryExists -Path $parent }

    if (Test-Path $VhdxPath) {
        # Pode ter ficado montado/preso de execu--es anteriores. Tentar desmontar e apagar de forma robusta.
        try { Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue } catch { }
        try {
            $v = Get-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
            if ($v -and $v.Attached) {
                try { Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue } catch { }
            }
        } catch { }

        $deleted = $false
        for ($i = 0; $i -lt 8; $i++) {
            try {
                if (Test-Path $VhdxPath) {
                    Remove-Item -LiteralPath $VhdxPath -Force -ErrorAction Stop
                }
                $deleted = -not (Test-Path $VhdxPath)
                if ($deleted) { break }
            } catch {
                Start-Sleep -Milliseconds 400
            }
        }
        if (-not $deleted -and (Test-Path $VhdxPath)) {
            throw "N-o foi poss-vel remover o VHDX existente: $VhdxPath. Ele pode estar em uso (montado/anexado). Feche o Hyper-V Manager/Discos, desmonte o VHD e tente novamente."
        }
    }

    $sizeBytes = $SizeMB * 1MB
    New-VHD -Path $VhdxPath -SizeBytes $sizeBytes -Dynamic | Out-Null

    $disk = Mount-VHD -Path $VhdxPath -PassThru
    try {
        $diskNumber = $disk.DiskNumber

        # MBR em vez de GPT - o scanner do Setup WinPE l- discos MBR de forma mais fi-vel
        Initialize-Disk -Number $diskNumber -PartitionStyle MBR -ErrorAction Stop | Out-Null

        # Parti--o ativa para se parecer com media de boot/remov-vel
        $part = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -IsActive -ErrorAction Stop

        # FAT32 em vez de NTFS - WinPE l- sempre FAT32 nesta fase inicial
        $vol = Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel "UNATTEND" -Confirm:$false -ErrorAction Stop

        # Esperar pela letra de drive (pode atrasar alguns ms)
        $driveLetter = $null
        for ($i = 0; $i -lt 10; $i++) {
            $driveLetter = (Get-Partition -DiskNumber $diskNumber | Where-Object { $_.DriveLetter -ne "`0" -and $_.DriveLetter } | Select-Object -First 1).DriveLetter
            if ($driveLetter) { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $driveLetter) { throw "N-o foi poss-vel obter a letra de drive do VHDX ap-s montagem." }

        $drive = "${driveLetter}:\"

        # Copiar conte-do (incluindo autounattend.xml) para a raiz
        Copy-Item -Path (Join-Path $SourceFolder "*") -Destination $drive -Recurse -Force

        # Sanity check - falhar de forma expl-cita se o XML n-o est- onde o Setup espera
        if (-not (Test-Path (Join-Path $drive "autounattend.xml"))) {
            throw "autounattend.xml n-o est- na raiz do VHDX ($drive). Verifique o conte-do de $SourceFolder."
        }

        Write-LogHost "VHDX de unattended criado com sucesso. autounattend.xml em: ${drive}autounattend.xml"
    } finally {
        Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
    }
}

function New-Windows10UnattendXml {
    param(
        [Parameter(Mandatory = $true)][string] $ComputerName,
        [Parameter(Mandatory = $true)][string] $UserName,
        [Parameter(Mandatory = $true)][string] $Password,
        [int] $VMGeneration = 1
    )
    # Nota: chave gen-rica para instalar Windows 10 Pro (n-o ativa). Ajuda a sele--o de edi--o.
    $productKey = "VK7JG-NPHTM-C97JM-9MPGT-3V66T"

    # Ajustar layout de disco para corresponder ao tipo de boot da VM:
    # - Gen1 (BIOS/Legacy): MBR (2 partições primárias)
    # - Gen2 (UEFI): GPT + EFI System + MSR
    $osPartitionId = if ($VMGeneration -eq 2) { 3 } else { 2 }
    $diskConfigurationBlock = if ($VMGeneration -eq 2) {
        @"
      <DiskConfiguration>
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>100</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>SYSTEM</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
"@
    } else {
        @"
      <DiskConfiguration>
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>100</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>SYSTEM</Label><Active>true</Active></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
"@
    }

    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>pt-PT</UILanguage></SetupUILanguage>
      <InputLocale>pt-PT</InputLocale>
      <SystemLocale>pt-PT</SystemLocale>
      <UILanguage>pt-PT</UILanguage>
      <UserLocale>pt-PT</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey><Key>$productKey</Key></ProductKey>
      </UserData>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/NAME</Key>
              <Value>Windows 10 Pro</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>$osPartitionId</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
      $diskConfigurationBlock
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>pt-PT</InputLocale>
      <SystemLocale>pt-PT</SystemLocale>
      <UILanguage>pt-PT</UILanguage>
      <UserLocale>pt-PT</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$ComputerName</ComputerName>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <Name>$UserName</Name>
            <Group>Administrators</Group>
            <Password><Value>$Password</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Username>$UserName</Username>
        <Password><Value>$Password</Value><PlainText>true</PlainText></Password>
        <Enabled>true</Enabled>
        <LogonCount>5</LogonCount>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>1</Order>
          <Description>Enable PowerShell remoting</Description>
          <!-- Marker para debug: confirma que o autounattend foi efetivamente aplicado no guest -->
          <CommandLine>powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -Path 'C:\unattend_applied.txt' -Value ('Applied:' + (Get-Date).ToString('o') + ' Host:' + $env:COMPUTERNAME + ' User: ${UserName}'); Enable-PSRemoting -Force"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

function Get-WindowsIsoDefaultLanguage {
    <#
    .SYNOPSIS
        Deteta o idioma default de um ISO do Windows (ex.: en-US, pt-PT) lendo sources\lang.ini.
    .DESCRIPTION
        O idioma do ISO afeta o comportamento do autounattend (Microsoft-Windows-International-Core-WinPE).
        Quando o autounattend fixa en-US mas o ISO é pt-PT (ou outro), o setup pode ignorar partes do unattended
        ou pedir input manual. Esta função tenta inferir o idioma do ISO para alinhar o autounattend.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $IsoPath,
        # Quando nao e possivel ler lang.ini, devolver $null (nao fingir en-US — evita logs enganadores).
        [string] $Fallback = $null
    )

    if (-not (Test-Path -LiteralPath $IsoPath)) { return $Fallback }

    $mounted = $false
    try {
        Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -ErrorAction Stop | Out-Null
        $mounted = $true
        Start-Sleep -Milliseconds 1200

        $vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume | Select-Object -First 1
        $isoDrive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $null }
        if (-not $isoDrive) { return $Fallback }

        $langIniCandidates = @(
            (Join-Path $isoDrive "sources\lang.ini"),
            (Join-Path $isoDrive "x64\sources\lang.ini"),
            (Join-Path $isoDrive "x86\sources\lang.ini")
        )

        foreach ($p in $langIniCandidates) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $lines = Get-Content -LiteralPath $p -ErrorAction SilentlyContinue
            if (-not $lines) { continue }
            foreach ($line in $lines) {
                if ($line -match '^\s*Default\s*=\s*([A-Za-z]{2}-[A-Za-z]{2})\s*$') {
                    return $Matches[1]
                }
            }
        }

        $wimLangs = @(Get-WindowsImageLanguagesFromInstallMedia -IsoRoot $isoDrive)
        if ($wimLangs.Count -gt 0) {
            $first = [string]$wimLangs[0]
            if ($first -match '^[a-zA-Z]{2}-[a-zA-Z]{2,}$') { return $first }
        }

        return $Fallback
    } catch {
        return $Fallback
    } finally {
        if ($mounted) {
            try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
    }
}

function Set-UnattendLanguageInPlace {
    <#
    .SYNOPSIS
        Substitui idioma/locale no autounattend.xml (WinPE + OOBE) para alinhar com o ISO.
    .DESCRIPTION
        Atualiza os nós mais comuns: SetupUILanguage/UILanguage, InputLocale, SystemLocale, UILanguage, UserLocale.
        Se o ficheiro não contiver esses nós, não faz nada (mantém comportamento default do ISO).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $UnattendXmlPath,
        [Parameter(Mandatory = $true)][string] $UiLanguage
    )

    if (-not (Test-Path -LiteralPath $UnattendXmlPath)) { return }
    if ([string]::IsNullOrWhiteSpace($UiLanguage)) { return }
    if ($UiLanguage -notmatch '^[a-zA-Z]{2}-[a-zA-Z]{2,}$') {
        Write-Warning "Set-UnattendLanguageInPlace: ignorando idioma invalido '$UiLanguage' (esperado xx-YY, ex.: en-US)."
        return
    }

    $xmlText = Get-Content -LiteralPath $UnattendXmlPath -Raw -ErrorAction Stop

    # WinPE / OOBE / general: substituir valores simples (ex.: en-US, pt-PT).
    $xmlText = [regex]::Replace($xmlText, '<UILanguage>\s*[^<]+\s*</UILanguage>', "<UILanguage>$UiLanguage</UILanguage>")
    $xmlText = [regex]::Replace($xmlText, '<InputLocale>\s*[^<]+\s*</InputLocale>', "<InputLocale>$UiLanguage</InputLocale>")
    $xmlText = [regex]::Replace($xmlText, '<SystemLocale>\s*[^<]+\s*</SystemLocale>', "<SystemLocale>$UiLanguage</SystemLocale>")
    $xmlText = [regex]::Replace($xmlText, '<UserLocale>\s*[^<]+\s*</UserLocale>', "<UserLocale>$UiLanguage</UserLocale>")

    Set-Content -LiteralPath $UnattendXmlPath -Value $xmlText -Encoding UTF8 -ErrorAction Stop
}

function Remove-UnattendInternationalSettings {
    <#
    .SYNOPSIS
        Remove componentes de idioma/locale do autounattend.xml para deixar o Setup seguir o idioma do ISO.
    .DESCRIPTION
        Em alguns ISOs não-en-US, forçar valores de locale pode fazer o unattended falhar ou pedir prompts.
        Esta função remove:
        - Microsoft-Windows-International-Core-WinPE (pass windowsPE)
        - Microsoft-Windows-International-Core (pass oobeSystem)
        Mantém o resto do autounattend intacto.
        NAO usar no autounattend custom Gen1 (en-US): sem International-Core-WinPE o WinPE nao aplica
        SetupUILanguage e o setup deixa de ser silencioso.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $UnattendXmlPath
    )

    if (-not (Test-Path -LiteralPath $UnattendXmlPath)) { return }

    $xmlText = Get-Content -LiteralPath $UnattendXmlPath -Raw -ErrorAction Stop

    # Remover bloco WinPE international core
    $xmlText = [regex]::Replace(
        $xmlText,
        '<component\s+name="Microsoft-Windows-International-Core-WinPE"[\s\S]*?</component>\s*',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # Remover bloco OOBE international core
    $xmlText = [regex]::Replace(
        $xmlText,
        '<component\s+name="Microsoft-Windows-International-Core"[\s\S]*?</component>\s*',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    Set-Content -LiteralPath $UnattendXmlPath -Value $xmlText -Encoding UTF8 -ErrorAction Stop
}

function Wait-VMHeartbeatOk {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [int] $TimeoutSeconds = 2400,
        [string] $LogPath,
        [int] $LogIntervalSeconds = 5
    )
    if ($script:DryRun) { return $true }
    $start = Get-Date
    $deadline = $start.AddSeconds($TimeoutSeconds)
    Write-SandboxLog -Message "A aguardar Heartbeat da VM '$VMName' (timeout ${TimeoutSeconds}s, intervalo ${LogIntervalSeconds}s)..." -LogPath $LogPath -Level "INFO"

    $lastPrimary = $null
    $lastSecondary = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $hb = Get-VMIntegrationService -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Heartbeat*" -or $_.Id -like "*Heartbeat*" } | Select-Object -First 1

            if (-not $hb) {
                $elapsed = [int]((Get-Date) - $start).TotalSeconds
                Write-SandboxLog -Message "Heartbeat: servico de integracao nao encontrado (ainda). elapsed=${elapsed}s" -LogPath $LogPath -Level "INFO"
            } else {
                $primary = $hb.PrimaryStatusDescription
                $secondary = $null
                try { $secondary = $hb.SecondaryStatusDescription } catch { }

                if ($primary -ne $lastPrimary -or $secondary -ne $lastSecondary) {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat status mudou: Primary='$primary' Secondary='$secondary' (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                    $lastPrimary = $primary
                    $lastSecondary = $secondary
                } else {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat: Primary='$primary' Secondary='$secondary' (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                }

                if ($primary -eq "OK") {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat da VM '$VMName' ficou OK após ${elapsed}s." -LogPath $LogPath -Level "INFO"
                    return $true
                }
            }
        } catch { }
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        Write-SandboxLog -Message "Heartbeat ainda nao OK. Tempo restante aproximado: ${remaining}s." -LogPath $LogPath -Level "INFO"

        Start-Sleep -Seconds $LogIntervalSeconds
    }
    Write-SandboxLog -Message "Timeout - espera do Heartbeat da VM '$VMName' ap-s ${TimeoutSeconds}s." -LogPath $LogPath -Level "WARN"
    return $false
}

function New-SandboxCredentialCandidates {
    param(
        [Parameter(Mandatory = $true)][string] $UserName,
        [Parameter(Mandatory = $true)][string] $Password,
        [string] $ComputerName
    )
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force

    $userNames = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        $userNames.Add($UserName)
    }

    # Se não houver domínio explícito, tentar variações comuns para conta local.
    $hasQualifier = ($UserName -match "\\") -or ($UserName -match "@")
    if (-not $hasQualifier) {
        $userNames.Add(".\$UserName")
        if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
            $userNames.Add("$ComputerName\$UserName")
        }
    }

    # Remover duplicados preservando ordem
    $seen = @{}
    $final = @()
    foreach ($u in $userNames) {
        if (-not $seen.ContainsKey($u)) {
            $seen[$u] = $true
            $final += $u
        }
    }

    return @($final | ForEach-Object { [pscredential]::new($_, $secure) })
}

function Wait-VMPowerShellDirectReady {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [pscredential] $Credential,
        [pscredential[]] $CredentialCandidates,
        # TimeoutSeconds:
        # - >0  : timeout normal
        # - <=0 : sem timeout (espera indefinidamente)
        [int] $TimeoutSeconds = 0,
        [string] $LogPath,
        [int] $LogIntervalSeconds = 10
    )
    if ($script:DryRun) { return $true }

    $candidates = @()
    if ($CredentialCandidates -and $CredentialCandidates.Count -gt 0) {
        $candidates = @($CredentialCandidates)
    } elseif ($Credential) {
        $candidates = @($Credential)
    } else {
        throw "Wait-VMPowerShellDirectReady: forneça -Credential ou -CredentialCandidates."
    }

    $start = Get-Date
    $deadline = $null
    if ($TimeoutSeconds -gt 0) { $deadline = $start.AddSeconds($TimeoutSeconds) }
    $timeoutLabel = if ($TimeoutSeconds -gt 0) { "${TimeoutSeconds}s" } else { "sem timeout" }
    Write-SandboxLog -Message "A aguardar PowerShell Direct na VM '$VMName' (timeout: $timeoutLabel, intervalo ${LogIntervalSeconds}s)..." -LogPath $LogPath -Level "INFO"

    $lastErr = $null
    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) { break }
        try {
            foreach ($cand in $candidates) {
                try {
                    # PowerShell Direct (Invoke-Command -VMName) não depende de rede/WinRM.
                    # Ele normalmente só começa a funcionar quando o Windows convidado já arrancou e aceita logon com as credenciais.
                    $null = Invoke-Command -VMName $VMName -Credential $cand -ScriptBlock { 1 } -ErrorAction Stop

                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "PowerShell Direct OK na VM '$VMName' após ${elapsed}s (user='$($cand.UserName)')." -LogPath $LogPath -Level "INFO"
                    return $cand
                } catch {
                    $msg = $($_.Exception.Message)
                    $lastErr = $msg
                }
            }
        } catch {
            $msg = $($_.Exception.Message)
            if ($msg -ne $lastErr) {
                $elapsed = [int]((Get-Date) - $start).TotalSeconds
                Write-SandboxLog -Message "PowerShell Direct ainda indisponível: $msg (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                $lastErr = $msg
            }
        }

        if ($deadline) {
            $remaining = [int]($deadline - (Get-Date)).TotalSeconds
            Write-SandboxLog -Message "PowerShell Direct ainda não OK. Tempo restante aproximado: ${remaining}s." -LogPath $LogPath -Level "INFO"
        } else {
            $elapsed = [int]((Get-Date) - $start).TotalSeconds
            $uList = ($candidates | ForEach-Object { $_.UserName }) -join ", "
            Write-SandboxLog -Message "PowerShell Direct ainda não OK (elapsed=${elapsed}s). Tentando users: $uList" -LogPath $LogPath -Level "INFO"
        }
        Start-Sleep -Seconds $LogIntervalSeconds
    }

    Write-SandboxLog -Message "Timeout - espera do PowerShell Direct na VM '$VMName' após ${TimeoutSeconds}s." -LogPath $LogPath -Level "WARN"
    return $null
}

function Get-SandboxGuestServiceName {
    param([string] $VMName)

    function _Normalize-Ascii {
        param([AllowNull()][string] $s)
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        try {
            $formD = $s.Normalize([Text.NormalizationForm]::FormD)
            $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $formD.ToCharArray()) {
                $uc = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
                if ($uc -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                    [void]$sb.Append($ch)
                }
            }
            return $sb.ToString().ToLowerInvariant()
        } catch {
            return ($s.ToLowerInvariant())
        }
    }

    try {
        $services = Get-VMIntegrationService -VMName $VMName -ErrorAction Stop

        # 1) Preferir match estável por Id/Description quando possível (alguns hosts expõem Ids como GUID).
        $svc = $services | Where-Object {
            ($_.Id -is [string] -and (($_.Id -like "*Guest*Service*") -or ($_.Id -like "*Guest*Interface*"))) -or
            ($_.Description -is [string] -and (($_.Description -like "*Guest Service*") -or ($_.Description -like "*Guest Service Interface*")))
        } | Select-Object -First 1
        if ($svc) { return $svc.Name }

        # 2) Fallback robusto por nome/descrição, ignorando acentos/idioma
        $targets = @(
            "guest service interface",
            "guest services",
            "interface de servico convidado",
            "servico convidado",
            "servicos de convidado"
        )

        $svc = $services | ForEach-Object {
            $n = _Normalize-Ascii $_.Name
            $d = _Normalize-Ascii $_.Description
            $hit = $false
            foreach ($t in $targets) {
                if ($n -like "*$t*" -or $d -like "*$t*") { $hit = $true; break }
            }
            if ($hit) { $_ }
        } | Select-Object -First 1

        if ($svc) { return $svc.Name }
    } catch { }
    return $null
}

function Enable-SandboxGuestService {
    param([string] $VMName)
    if ($script:DryRun) { return }
    $name = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $name) {
        Write-LogWarning "Guest Service (Integration Service) n-o encontrado/indispon-vel na VM '$VMName'."
        Write-LogWarning "Isto normalmente significa que o Windows na VM ainda n-o est- instalado/arrancado, ou que o servi-o de integra--o 'Guest Services' n-o est- dispon-vel."
        return
    }
    Enable-VMIntegrationService -VMName $VMName -Name $name -ErrorAction SilentlyContinue
}

function Disable-SandboxGuestService {
    param([string] $VMName)
    if ($script:DryRun) { return }
    $name = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $name) { return }
    Disable-VMIntegrationService -VMName $VMName -Name $name -ErrorAction SilentlyContinue
}

function Ensure-DirectoryExists {
    param(
        [string] $Path
    )
    if (Test-Path $Path) { return }
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Criaria diret-rio: $Path"
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-Directory {
    param(
        [string] $Path
    )
    Ensure-DirectoryExists -Path $Path
}

function Test-SandboxPrerequisites {
    [CmdletBinding()]
    param()

    $hv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
    if ($hv.State -ne "Enabled") {
        throw "Hyper-V n-o est- ativo. Ative Microsoft-Hyper-V e reinicie."
    }
}

function Ensure-VMSwitchExists {
    param(
        [string] $SwitchName
    )
    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $existing) {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Criaria VMSwitch '$SwitchName' (Internal)."
        } else {
            New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        }
    }
}

function Ensure-VMSwitch {
    param(
        [string] $Name
    )
    Ensure-VMSwitchExists -SwitchName $Name
}

function Get-SandboxNetAdapter {
    param(
        [string] $SwitchName
    )
    $adapter = $null
    try {
        $expectedName = "vEthernet ($SwitchName)"
        $adapter = Get-NetAdapter -Name $expectedName -ErrorAction SilentlyContinue
    } catch { $adapter = $null }

    if (-not $adapter) {
        $adapter = Get-NetAdapter | Where-Object { $_.Name -eq "vEthernet ($SwitchName)" -or $_.Name -like "*$SwitchName*" } | Select-Object -First 1
    }
    return $adapter
}

function Set-SandboxHostIpIfNeeded {
    param(
        [string] $SwitchName,
        [string] $IpAddress = "192.168.100.1",
        [int]    $PrefixLength = 24
    )
    $adapter = Get-SandboxNetAdapter -SwitchName $SwitchName
    if (-not $adapter) {
        Write-LogHost "Adaptador do switch '$SwitchName' n-o encontrado (ignorado)."
        return
    }

    $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not ($existing | Where-Object { $_.IPAddress -eq $IpAddress })) {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Atribuiria IP ${IpAddress}/${PrefixLength} ao adaptador '$($adapter.Name)'."
        } else {
            try {
                New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IpAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
                Write-LogHost "IP ${IpAddress}/${PrefixLength} atribu-do ao adaptador do switch."
            } catch {
                Write-LogWarning "N-o foi poss-vel atribuir IP ${IpAddress}/${PrefixLength}: $($_.Exception.Message)"
            }
        }
    } else {
        Write-LogHost "Adaptador j- tem o IP ${IpAddress}/${PrefixLength} configurado."
    }
}

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
        # Default mais rápido e determinístico: evitar espera "sem timeout" (0) quando há credenciais.
        if ($PowerShellDirectTimeoutSeconds -le 0) { $PowerShellDirectTimeoutSeconds = 240 }
        Write-LogHost "A aguardar arranque da VM (PowerShell Direct, verificação a cada 2s)..."
        return (Wait-VMPowerShellDirectReady -VMName $VMName -Credential $Credential -CredentialCandidates $CredentialCandidates -TimeoutSeconds $PowerShellDirectTimeoutSeconds -LogPath $LogPath -LogIntervalSeconds 2)
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
            # Em alguns hosts, os campos s-o PrimaryStatusDescription/SecondaryStatusDescription
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

# --- Canal serial COM1 (Gen1) ↔ Named Pipe no host (relatório texto, START_OF_REPORT … END_OF_REPORT) ---

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


Export-ModuleMember -Function * -Variable DryRun