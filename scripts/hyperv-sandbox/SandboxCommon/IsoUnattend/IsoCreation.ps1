function New-IsoFromFolder {
    <#
    .SYNOPSIS
        Cria um ISO bootável a partir de uma pasta usando oscdimg.exe (Windows ADK)
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
           O WinPE procura autounattend.xml em \Windows\System32\ quando não
           encontra na raiz -- isto garante automação mesmo em ISOs MCT.
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
        # 1. Montar ISO e copiar conteúdo
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

        # 2. Colocar autounattend.xml na raiz do ISO (método clássico)
        Copy-Item -Path $UnattendXmlPath -Destination (Join-Path $tmpDir "autounattend.xml") -Force
        Write-LogHost "autounattend.xml copiado para raiz do ISO."

        # 3. Injetar autounattend.xml dentro do boot.wim (WinPE)
        #    O WinPE (index 2 do boot.wim) procura autounattend.xml em:
        #    - raiz de qualquer drive (A:, B:, C:, D:, etc.)
        #    - \Windows\System32\ no WinPE (X:\Windows\System32\)
        #    Injetamos em \Windows\System32\ para garantia máxima.
        $bootWimSrc = Join-Path $tmpDir "sources\boot.wim"
        if (Test-Path $bootWimSrc) {
            Write-LogHost "A injetar autounattend.xml no boot.wim (WinPE)..."
            try {
                # boot.wim pode ser read-only (vem do ISO) -- remover atributo
                Set-ItemProperty -Path $bootWimSrc -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

                # Montar index 2 (WinPE Setup -- index 1 é o Setup loader, index 2 é o WinPE completo)
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

        # 4. Criar ISO bootável com oscdimg
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

