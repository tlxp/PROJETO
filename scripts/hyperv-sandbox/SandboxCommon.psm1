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

function New-IsoFromFolder {
    <#
    .SYNOPSIS
        Cria um ISO a partir de uma pasta usando IMAPI2 (built-in no Windows).
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

    if (-not (Test-Path $SourceFolder)) { throw "Pasta não existe: $SourceFolder" }
    $parent = Split-Path -Parent $IsoPath
    if ($parent) { Ensure-DirectoryExists -Path $parent }

    throw "New-IsoFromFolder não é suportado neste sistema (dependência COM IMAPI2FS). Use New-UnattendVhdx em vez disso."
}

function New-UnattendVhdx {
    <#
    .SYNOPSIS
        Cria um pequeno VHDX com um volume e copia ficheiros (ex.: autounattend.xml) para a raiz.
    .DESCRIPTION
        Este VHDX pode ser anexado à VM como disco adicional; o Windows Setup procura autounattend.xml
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
    if (-not (Test-Path $SourceFolder)) { throw "Pasta não existe: $SourceFolder" }
    $parent = Split-Path -Parent $VhdxPath
    if ($parent) { Ensure-DirectoryExists -Path $parent }

    # Criar VHDX
    if (Test-Path $VhdxPath) {
        Remove-Item -LiteralPath $VhdxPath -Force -ErrorAction SilentlyContinue
    }
    $sizeBytes = $SizeMB * 1MB
    New-VHD -Path $VhdxPath -SizeBytes $sizeBytes -Dynamic | Out-Null
    $disk = Mount-VHD -Path $VhdxPath -PassThru
    try {
        $diskNumber = $disk.DiskNumber
        Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null
        $part = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
        $vol = Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel "UNATTEND" -Confirm:$false -ErrorAction Stop
        $drive = $vol.DriveLetter + ":\"
        Copy-Item -Path (Join-Path $SourceFolder "*") -Destination $drive -Recurse -Force
    } finally {
        Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
    }
}

function New-Windows10UnattendXml {
    param(
        [Parameter(Mandatory = $true)][string] $ComputerName,
        [Parameter(Mandatory = $true)][string] $UserName,
        [Parameter(Mandatory = $true)][string] $Password
    )
    # Nota: chave genérica para instalar Windows 10 Pro (não ativa). Ajuda a seleção de edição.
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
        [int] $TimeoutSeconds = 2400
    )
    if ($script:DryRun) { return $true }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $hb = Get-VMIntegrationService -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Heartbeat*" -or $_.Id -like "*Heartbeat*" } | Select-Object -First 1
            if ($hb -and $hb.PrimaryStatusDescription -eq "OK") { return $true }
        } catch { }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Get-SandboxGuestServiceName {
    param([string] $VMName)
    try {
        $services = Get-VMIntegrationService -VMName $VMName -ErrorAction Stop
        # 1) Preferir o Id (mais estável que o Name em idiomas diferentes)
        $svc = $services | Where-Object {
            ($_.Id -like "*Guest*Service*") -or ($_.Id -like "*Guest*Interface*") -or ($_.Id -like "*Guest*")
        } | Select-Object -First 1

        if ($svc) { return $svc.Name }

        # 2) Fallback por Name/Description (heurístico)
        $svc = $services | Where-Object {
            ($_.Name -like "*Guest Service*") -or
            ($_.Name -like "*Serviço*Convidado*") -or
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
        Write-LogWarning "Guest Service (Integration Service) não encontrado/indisponível na VM '$VMName'."
        Write-LogWarning "Isto normalmente significa que o Windows na VM ainda não está instalado/arrancado, ou que o serviço de integração 'Guest Services' não está disponível."
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
        Write-LogHost "[DRY-RUN] Criaria diretório: $Path"
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
        throw "Hyper-V não está ativo. Ative Microsoft-Hyper-V e reinicie."
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
        Write-LogHost "Adaptador do switch '$SwitchName' não encontrado (ignorado)."
        return
    }

    $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not ($existing | Where-Object { $_.IPAddress -eq $IpAddress })) {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Atribuiria IP ${IpAddress}/${PrefixLength} ao adaptador '$($adapter.Name)'."
        } else {
            try {
                New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IpAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
                Write-LogHost "IP ${IpAddress}/${PrefixLength} atribuído ao adaptador do switch."
            } catch {
                Write-LogWarning "Não foi possível atribuir IP ${IpAddress}/${PrefixLength}: $($_.Exception.Message)"
            }
        }
    } else {
        Write-LogHost "Adaptador já tem o IP ${IpAddress}/${PrefixLength} configurado."
    }
}

function Start-SandboxVM {
    param(
        [string] $VMName,
        [int]    $BootWaitSeconds = 60
    )
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        throw "VM '$VMName' não encontrada."
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
        throw "Guest Services não disponível na VM '$VMName'. Não é possível usar Copy-VMFile. Instale/arranque o Windows na VM e garanta que o Integration Service 'Guest Services' existe/está disponível."
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

