<#
.SYNOPSIS
    Corre DENTRO DA VM. Instala winget e software comum via winget.
    Grava estado de verificação em JSON para o host confirmar.
.DESCRIPTION
    Fluxo:
      [1] Garantir que o winget está disponível (instala App Installer se necessário)
      [2] Instalar lista de pacotes via winget
      [3] Verificar que cada pacote está realmente instalado
      [4] Gravar prepare_winget_state.json + prepare_winget_ready.flag
      [5] Configurar ambiente "realista" (hostname, serviços, etc.)

    O host (05-FirstTimeVmSetup.ps1) lê o JSON para confirmar allVerified=true
    antes de cortar a internet e criar o snapshot.

.PARAMETER InstallCommonSoftware
    Switch obrigatório para activar a instalação (proteção contra execução acidental).
.PARAMETER AllowWithoutWinget
    Se definido, não falha quando o winget não está disponível (ambiente sem App Installer).
.PARAMETER WorkDir
    Directório de trabalho na VM. Predefinição: C:\analysis_work
#>
param(
    [switch] $InstallCommonSoftware,
    [switch] $AllowWithoutWinget,
    [string] $WorkDir = "C:\analysis_work",
    # Se fornecido, usa APENAS bundle offline (sem downloads).
    # Deve conter: AppInstaller.msixbundle + VCLibs + UI.Xaml
    [string] $OfflineWingetPath = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function LogMsg {
    param([string]$msg, [string]$level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts][$level] $msg"
}

function LogWarn  { param([string]$m) LogMsg $m "WARN"  }
function LogError { param([string]$m) LogMsg $m "ERROR" }

function Use-Tls12 {
    try {
        # Em algumas imagens do Windows, o default pode não incluir TLS 1.2.
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
    } catch { }
}

function Download-FileRobust {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $DestinationPath,
        [int] $Retries = 4
    )

    Use-Tls12

    $lastErr = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if (Test-Path -LiteralPath $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }

            # Preferir BITS se disponível (mais resiliente a falhas momentâneas)
            $hasBits = $false
            try { $hasBits = $null -ne (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) } catch { }
            if ($hasBits) {
                Start-BitsTransfer -Source $Url -Destination $DestinationPath -ErrorAction Stop
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            }

            if (-not (Test-Path -LiteralPath $DestinationPath)) {
                throw "Download terminou mas o ficheiro não existe: $DestinationPath"
            }
            return
        } catch {
            $lastErr = $_.Exception.Message
            if ($i -lt $Retries) { Start-Sleep -Seconds ([Math]::Min(10, 2 * $i)) }
        }
    }
    throw "Falha ao descarregar após ${Retries} tentativas. URL=$Url. Erro: $lastErr"
}

function Test-WingetAvailable {
    param([string] $WingetPath = "")
    try {
        $exe = $WingetPath
        if ([string]::IsNullOrWhiteSpace($exe)) {
            $cmd = Get-Command winget -ErrorAction SilentlyContinue
            $exe = if ($cmd) { $cmd.Source } else { "" }
        }
        if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
        $null = & $exe --version 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

if (-not $InstallCommonSoftware) {
    LogError "Use o switch -InstallCommonSoftware para confirmar a instalação."
    exit 1
}

# Garantir pasta de trabalho
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

$StateJsonPath = Join-Path $WorkDir "prepare_winget_state.json"
$ReadyFlagPath = Join-Path $WorkDir "prepare_winget_ready.flag"

# Limpar ficheiros de estado anteriores
Remove-Item -LiteralPath $StateJsonPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ReadyFlagPath -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# [1] Lista de pacotes a instalar
#     id winget  |  nome amigável  |  verificação alternativa (exe/reg)
# ---------------------------------------------------------------------------
$Packages = @(
    [PSCustomObject]@{
        Id          = "7zip.7zip"
        FriendlyName = "7-Zip"
        VerifyExe   = @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")
    },
    [PSCustomObject]@{
        Id          = "Notepad++.Notepad++"
        FriendlyName = "Notepad++"
        VerifyExe   = @("C:\Program Files\Notepad++\notepad++.exe", "C:\Program Files (x86)\Notepad++\notepad++.exe")
    },
    [PSCustomObject]@{
        Id          = "Google.Chrome"
        FriendlyName = "Google Chrome"
        VerifyExe   = @(
            "C:\Program Files\Google\Chrome\Application\chrome.exe",
            "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
        )
    },
    [PSCustomObject]@{
        Id          = "Adobe.Acrobat.Reader.64-bit"
        FriendlyName = "Adobe Acrobat Reader"
        VerifyExe   = @(
            "C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
            "C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
        )
    },
    [PSCustomObject]@{
        Id          = "VideoLAN.VLC"
        FriendlyName = "VLC"
        VerifyExe   = @(
            "C:\Program Files\VideoLAN\VLC\vlc.exe",
            "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        )
    }
)

# ---------------------------------------------------------------------------
# [2] Garantir winget disponível
# ---------------------------------------------------------------------------
LogMsg "=== Prepare-RealisticEnvironment ==="
LogMsg "[1] A verificar winget..."

function Get-WingetPath {
    # Tentar directo
    try {
        $w = Get-Command winget -ErrorAction SilentlyContinue
        if ($w) { return $w.Source }
    } catch {}

    # Localizar via AppX / pasta local
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:PROGRAMFILES\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    foreach ($c in $candidates) {
        $found = Get-Item -Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    # Pesquisa em WindowsApps (pode precisar de permissão)
    try {
        $wa = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wa) { return $wa.FullName }
    } catch {}

    return $null
}

$wingetPath = Get-WingetPath

if (-not $wingetPath) {
    LogWarn "winget não encontrado. A tentar instalar/registar App Installer..."

    # Tentar re-registar pacote existente
    try {
        Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 5
        $wingetPath = Get-WingetPath
    } catch {
        LogWarn "Re-registo do App Installer falhou: $($_.Exception.Message)"
    }
}

if (-not $wingetPath) {
    LogWarn "A tentar instalar App Installer via download directo..."
    try {
        # Bundle offline (preferencial / opcionalmente forçado por parâmetro)
        $offlineDir = if (-not [string]::IsNullOrWhiteSpace($OfflineWingetPath)) { $OfflineWingetPath } else { (Join-Path $WorkDir "offline\winget") }
        $offlineVclibs = Join-Path $offlineDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $offlineXaml   = Join-Path $offlineDir "Microsoft.UI.Xaml.2.8.x64.appx"
        $offlineAppIns = Join-Path $offlineDir "AppInstaller.msixbundle"

        if ((Test-Path -LiteralPath $offlineVclibs) -and (Test-Path -LiteralPath $offlineXaml) -and (Test-Path -LiteralPath $offlineAppIns)) {
            LogMsg "  Bundle offline encontrado em $offlineDir. A instalar dependências + App Installer..."
            Add-AppxPackage -Path $offlineVclibs -ErrorAction SilentlyContinue | Out-Null
            Add-AppxPackage -Path $offlineXaml   -ErrorAction SilentlyContinue | Out-Null
            Add-AppxPackage -Path $offlineAppIns -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds 8
            $wingetPath = Get-WingetPath
        } else {
            if (Test-Path -LiteralPath $offlineDir) {
                LogWarn "  Pasta offline existe mas faltam ficheiros. Esperados:"
                LogWarn "    - $offlineVclibs"
                LogWarn "    - $offlineXaml"
                LogWarn "    - $offlineAppIns"
            }
        }

        if ($wingetPath) {
            LogMsg "  winget ficou disponível via bundle offline."
        } else {
            if (-not [string]::IsNullOrWhiteSpace($OfflineWingetPath)) {
                # Modo offline 100%: não tentar downloads.
                throw "OfflineWingetPath foi fornecido mas o bundle offline não estava completo ou a instalação falhou."
            }

            $appInstallerUrl  = "https://aka.ms/getwinget"
            $appInstallerDest = Join-Path $env:TEMP "AppInstaller.msixbundle"
            # VCLibs (dependência)
            $vclibsUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            $vclibsDest = Join-Path $env:TEMP "VCLibs.appx"
            # UI.Xaml (dependência)
            $xamlUrl    = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
            $xamlDest   = Join-Path $env:TEMP "UIXaml.appx"

            LogMsg "  A descarregar VCLibs..."
            Download-FileRobust -Url $vclibsUrl -DestinationPath $vclibsDest
            LogMsg "  A descarregar UI.Xaml..."
            Download-FileRobust -Url $xamlUrl -DestinationPath $xamlDest
            LogMsg "  A descarregar App Installer..."
            Download-FileRobust -Url $appInstallerUrl -DestinationPath $appInstallerDest

            Add-AppxPackage -Path $vclibsDest   -ErrorAction SilentlyContinue | Out-Null
            Add-AppxPackage -Path $xamlDest     -ErrorAction SilentlyContinue | Out-Null
            Add-AppxPackage -Path $appInstallerDest -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds 8
            $wingetPath = Get-WingetPath
        }
    } catch {
        LogWarn "Instalação do App Installer falhou: $($_.Exception.Message)"
    }
}

$wingetFound = ($null -ne $wingetPath -and $wingetPath -ne "")
LogMsg "winget encontrado: $wingetFound $(if ($wingetFound) { "-> $wingetPath" })"

if ($wingetFound -or (Test-WingetAvailable -WingetPath $wingetPath)) {
    LogMsg "Winget instalado/encontrado. A aguardar registo no sistema..."

    # Espera ativa até winget responder (pode demorar 30-60s após instalar App Installer)
    $maxWait = 60
    $waited = 0
    $wingetReady = $false
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 2
        $waited += 2

        $ok = Test-WingetAvailable -WingetPath $wingetPath
        if ($ok) {
            $wingetReady = $true
            LogMsg "Winget pronto após ${waited}s"
            break
        }
        LogMsg "Aguardando winget... (${waited}s)"
    }

    if (-not $wingetReady) {
        LogWarn "Winget não respondeu após ${maxWait}s"
        if (-not $AllowWithoutWinget) {
            throw "Winget instalado mas não responde"
        }
    } else {
        # Atualizar caminho caso só tenha ficado visível agora
        if (-not $wingetFound) { $wingetPath = Get-WingetPath }
        $wingetFound = ($null -ne $wingetPath -and $wingetPath -ne "")
    }
}

if (-not $wingetFound) {
    if ($AllowWithoutWinget) {
        LogWarn "winget não disponível mas AllowWithoutWinget=true. A gravar estado parcial."
        $state = @{
            wingetFound = $false
            allVerified = $false
            allowedWithoutWinget = $true
            packages    = @()
            timestamp   = (Get-Date -Format "o")
        }
        $state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateJsonPath -Encoding UTF8
        exit 0
    } else {
        throw "winget não disponível e AllowWithoutWinget não foi especificado. Abortar."
    }
}

# Aceitar acordos do winget silenciosamente (necessário na primeira execução)
try {
    & $wingetPath settings --enable InstallerHashOverride 2>&1 | Out-Null
} catch {}

# ---------------------------------------------------------------------------
# [3] Instalar pacotes
# ---------------------------------------------------------------------------
LogMsg "[2] A instalar pacotes ($($Packages.Count) pacotes)..."

$installResults = @{}

foreach ($pkg in $Packages) {
    LogMsg "  -> A instalar $($pkg.FriendlyName) [$($pkg.Id)]..."

    # Verificar se já está instalado antes de tentar instalar
    $alreadyInstalled = $false
    foreach ($exe in $pkg.VerifyExe) {
        if (Test-Path $exe) {
            $alreadyInstalled = $true
            LogMsg "     Já instalado: $exe"
            break
        }
    }

    if ($alreadyInstalled) {
        $installResults[$pkg.Id] = @{ installed = $true; skipped = $true; error = "" }
        continue
    }

    $installOk  = $false
    $installErr = ""

    try {
        $result = & $wingetPath install --id $pkg.Id `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity `
            2>&1

        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0 -or $exitCode -eq -1978335135) {
            # -1978335135 = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED (0x8A150021)
            $installOk = $true
            LogMsg "     OK (exit $exitCode)"
        } else {
            $installErr = "winget saiu com código $exitCode. Output: $($result -join ' ')"
            LogWarn "     FALHA (exit $exitCode): $installErr"
        }
    } catch {
        $installErr = $_.Exception.Message
        LogWarn "     EXCEPÇÃO: $installErr"
    }

    $installResults[$pkg.Id] = @{
        installed = $installOk
        skipped   = $false
        error     = $installErr
    }

    # Pequena pausa entre instalações para evitar conflitos
    Start-Sleep -Seconds 3
}

# ---------------------------------------------------------------------------
# [4] Verificar instalação real (exe no disco)
# ---------------------------------------------------------------------------
LogMsg "[3] A verificar instalação dos pacotes..."

$pkgStates = @()
$allVerified = $true

foreach ($pkg in $Packages) {
    $found = $false
    $foundPath = ""
    foreach ($exe in $pkg.VerifyExe) {
        if (Test-Path $exe) {
            $found     = $true
            $foundPath = $exe
            break
        }
    }

    # Fallback: pesquisar no registo de desinstalação
    if (-not $found) {
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($rp in $regPaths) {
            $entry = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*$($pkg.FriendlyName)*" } |
                     Select-Object -First 1
            if ($entry) {
                $found     = $true
                $foundPath = "registry: $($entry.DisplayName)"
                break
            }
        }
    }

    $installInfo = $installResults[$pkg.Id]

    $pkgState = [PSCustomObject]@{
        id           = $pkg.Id
        friendlyName = $pkg.FriendlyName
        verified     = $found
        foundPath    = $foundPath
        installed    = if ($installInfo) { $installInfo.installed } else { $false }
        skipped      = if ($installInfo) { $installInfo.skipped   } else { $false }
        error        = if ($installInfo) { $installInfo.error      } else { "" }
    }
    $pkgStates += $pkgState

    if ($found) {
        LogMsg "  [OK] $($pkg.FriendlyName): $foundPath"
    } else {
        LogWarn "  [FALHA] $($pkg.FriendlyName): não encontrado no disco nem no registo."
        $allVerified = $false
    }
}

LogMsg "allVerified = $allVerified"

# ---------------------------------------------------------------------------
# [5] Configurar ambiente "realista"
# ---------------------------------------------------------------------------
LogMsg "[4] A configurar ambiente realista..."

# Desactivar Windows Update automático (evita que o sample seja perturbado por actualizações)
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoUpdate" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  Windows Update automático desactivado."
} catch {
    LogWarn "  Não foi possível desactivar Windows Update: $($_.Exception.Message)"
}

# Desactivar hibernação e ecrã de bloqueio (VM deve ficar activa durante análise)
try {
    powercfg /hibernate off 2>&1 | Out-Null
    powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
    powercfg /change monitor-timeout-ac 0 2>&1 | Out-Null
    LogMsg "  Hibernação/standby desactivados."
} catch {
    LogWarn "  Não foi possível configurar power: $($_.Exception.Message)"
}

# Desactivar SmartScreen para não bloquear samples
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" `
        -Name "SmartScreenEnabled" -Value "Off" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "EnableSmartScreen" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  SmartScreen desactivado."
} catch {
    LogWarn "  Não foi possível desactivar SmartScreen: $($_.Exception.Message)"
}

# Desactivar UAC (facilita a execução de samples como admin)
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  UAC desactivado."
} catch {
    LogWarn "  Não foi possível desactivar UAC: $($_.Exception.Message)"
}

# Criar pasta de trabalho de análise
$analysisDir = "C:\analysis_work"
if (-not (Test-Path $analysisDir)) {
    New-Item -ItemType Directory -Path $analysisDir -Force | Out-Null
    LogMsg "  Pasta $analysisDir criada."
}

# Criar documentos "isca" para o ambiente parecer usado
$decoyDocs = @(
    @{ Path = "$env:USERPROFILE\Documents\relatorio_q3_2024.txt"; Content = "Relatorio Q3 2024`nTotal vendas: 1.250.000 EUR`nMargem: 18,3%" },
    @{ Path = "$env:USERPROFILE\Documents\passwords_backup.txt";  Content = "# Notas pessoais - NÃO PARTILHAR`nEmail: analyst@empresa.pt`nVPN: changeme123" },
    @{ Path = "$env:USERPROFILE\Desktop\notas.txt";               Content = "Reunião amanhã às 10h. Ver email do João sobre contrato." }
)

foreach ($doc in $decoyDocs) {
    try {
        $dir = Split-Path $doc.Path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $doc.Path -Value $doc.Content -Encoding UTF8 -Force
    } catch {
        LogWarn "  Não foi possível criar ficheiro isca: $($doc.Path)"
    }
}
LogMsg "  Ficheiros isca criados."

# ---------------------------------------------------------------------------
# [6] Gravar estado final
# ---------------------------------------------------------------------------
LogMsg "[5] A gravar estado final..."

$state = @{
    wingetFound          = $wingetFound
    wingetPath           = $wingetPath
    allVerified          = $allVerified
    allowedWithoutWinget = $AllowWithoutWinget.IsPresent
    packages             = $pkgStates
    timestamp            = (Get-Date -Format "o")
    hostname             = $env:COMPUTERNAME
    user                 = $env:USERNAME
}

$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateJsonPath -Encoding UTF8
LogMsg "  Estado gravado: $StateJsonPath"

if ($allVerified) {
    Set-Content -Path $ReadyFlagPath -Value "ready" -Encoding UTF8
    LogMsg "  Flag de pronto criada: $ReadyFlagPath"
} else {
    LogWarn "  allVerified=false. Flag NOT criada. O host irá abortar o setup."
}

LogMsg ""
LogMsg "=== Prepare-RealisticEnvironment concluído. allVerified=$allVerified ==="

if (-not $allVerified) {
    # Saída com código de erro para o host detectar
    exit 1
}