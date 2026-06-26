# --- Módulo: VhdxUnattend.ps1 ---
# --- VHDX FAT32 com autounattend para boot ---

# --- Criação de VHDX com autounattend.xml ---
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
    if (-not (Test-Path $SourceFolder)) { throw "Pasta n-o existe: $SourceFolder" }
    $parent = Split-Path -Parent $VhdxPath
    if ($parent) { Ensure-DirectoryExists -Path $parent }

    if (Test-Path $VhdxPath) {
        # Remover VHDX existente (pode ter ficado montado de execuções anteriores)
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

        # MBR em vez de GPT — o scanner do Setup WinPE lê discos MBR de forma mais fiável
        Initialize-Disk -Number $diskNumber -PartitionStyle MBR -ErrorAction Stop | Out-Null

        # Partição ativa para se parecer com media de boot/removível
        $part = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -IsActive -ErrorAction Stop

        # FAT32 em vez de NTFS — WinPE lê sempre FAT32 nesta fase inicial
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

        # Copiar conteúdo (incluindo autounattend.xml) para a raiz
        Copy-Item -Path (Join-Path $SourceFolder "*") -Destination $drive -Recurse -Force

        # Validar que o XML está na raiz, onde o Setup o procura
        if (-not (Test-Path (Join-Path $drive "autounattend.xml"))) {
            throw "autounattend.xml n-o est- na raiz do VHDX ($drive). Verifique o conte-do de $SourceFolder."
        }

        Write-LogHost "VHDX de unattended criado com sucesso. autounattend.xml em: ${drive}autounattend.xml"
    } finally {
        Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue
    }
}

