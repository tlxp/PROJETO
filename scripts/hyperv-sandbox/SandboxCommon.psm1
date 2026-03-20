param(
    [switch] $DryRun
)

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

        # Sanity check - falhar de forma expl-cita se o XML n-o estiver onde o Setup espera
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
            <PartitionID>3</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
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
          <CommandLine>powershell -NoProfile -ExecutionPolicy Bypass -Command "Enable-PSRemoting -Force"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

function Wait-VMHeartbeatOk {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [int] $TimeoutSeconds = 2400,
        [string] $LogPath
    )
    if ($script:DryRun) { return $true }
    $start = Get-Date
    $deadline = $start.AddSeconds($TimeoutSeconds)
    Write-SandboxLog -Message "A aguardar Heartbeat da VM '$VMName' (timeout ${TimeoutSeconds}s)..." -LogPath $LogPath -Level "INFO"
    while ((Get-Date) -lt $deadline) {
        try {
            $hb = Get-VMIntegrationService -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Heartbeat*" -or $_.Id -like "*Heartbeat*" } | Select-Object -First 1
            if ($hb -and $hb.PrimaryStatusDescription -eq "OK") {
                $elapsed = [int]((Get-Date) - $start).TotalSeconds
                Write-SandboxLog -Message "Heartbeat da VM '$VMName' ficou OK ap-s ${elapsed}s." -LogPath $LogPath -Level "INFO"
                return $true
            }
        } catch { }
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        Write-SandboxLog -Message "Heartbeat ainda n-o est- OK para a VM '$VMName'. Tempo restante aproximado: ${remaining}s." -LogPath $LogPath -Level "INFO"
        Start-Sleep -Seconds 15
    }
    Write-SandboxLog -Message "Timeout - espera do Heartbeat da VM '$VMName' ap-s ${TimeoutSeconds}s." -LogPath $LogPath -Level "WARN"
    return $false
}

function Get-SandboxGuestServiceName {
    param([string] $VMName)
    try {
        $services = Get-VMIntegrationService -VMName $VMName -ErrorAction Stop
        # 1) Preferir o Id (mais est-vel que o Name em idiomas diferentes)
        $svc = $services | Where-Object {
            ($_.Id -like "*Guest*Service*") -or ($_.Id -like "*Guest*Interface*") -or ($_.Id -like "*Guest*")
        } | Select-Object -First 1

        if ($svc) { return $svc.Name }

        # 2) Fallback por Name/Description (heur-stico)
        $svc = $services | Where-Object {
            ($_.Name -like "*Guest Service*") -or
            ($_.Name -like "*Servi-o*Convidado*") -or
            ($_.Name -like "*Guest*Interface*") -or
            ($_.Name -like "*Convidado*Interface*") -or
            ($_.Description -like "*Guest Service*") -or
            ($_.Description -like "*convidad*service*") -or
            ($_.Description -like "*Guest Service Interface*")
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

function Start-SandboxVM {
    param(
        [string] $VMName,
        [int]    $BootWaitSeconds = 60
    )
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        throw "VM '$VMName' n-o encontrada."
    }
    if ($vm.State -ne "Running") {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Arrancaria a VM '$VMName'."
        } else {
            Start-VM -Name $VMName | Out-Null
        }
    }
    if (-not $script:DryRun) {
        Write-LogHost "A aguardar $BootWaitSeconds s pelo arranque da VM..."
        Start-Sleep -Seconds $BootWaitSeconds
    }
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

function New-SandboxNamedPipeServer {
    param(
        [string] $PipeName,
        [int]    $InBufferSize = 4096,
        [int]    $OutBufferSize = 4096
    )
    $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity
    $adminRule = New-Object System.IO.Pipes.PipeAccessRule(
        "Administrators",
        [System.IO.Pipes.PipeAccessRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $pipeSecurity.AddAccessRule($adminRule)

    $pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
        $PipeName,
        [System.IO.Pipes.PipeDirection]::In,
        1,
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
        $pipe = New-SandboxNamedPipeServer -PipeName $PipeName
        $pipe.WaitForConnection()

        $reader = New-Object System.IO.StreamReader($pipe)
        $lines = New-Object System.Collections.ArrayList
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

        while ($pipe.IsConnected -and ([DateTime]::UtcNow -lt $deadline)) {
            if ($reader.Peek() -ge 0) {
                $line = $reader.ReadLine()
                if ($null -eq $line) { break }
                [void]$lines.Add($line)
            }
            else {
                Start-Sleep -Milliseconds 200
            }
        }

        $reader.Close()
        $pipe.Close()

        $content = $lines -join "`r`n"
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)
        return $lines.Count
    }
    finally {
        if ($null -ne $pipe -and $pipe.IsConnected) {
            try { $pipe.Close() } catch { }
        }
    }
}

Export-ModuleMember -Function * -Variable DryRun