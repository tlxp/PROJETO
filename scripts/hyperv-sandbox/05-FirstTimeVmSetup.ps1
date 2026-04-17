<#
.SYNOPSIS
    Primeira entrada na VM: liga internet temporária, instala software (winget),
    verifica instalação real, corta internet MESMO A SÉRIO, guarda snapshot CleanState.
.DESCRIPTION
    A correr NO HOST. Fluxo completo:

      [1/11] Parar VM (estado limpo)
      [2/11] Garantir switch externo (criar se necessário) + adicionar adaptador temporário
      [3/11] Verificar conectividade real do host (sem internet no host = não haverá na VM)
      [4/11] Arrancar VM + aguardar PowerShell Direct
      [5/11] Ativar Guest Service Interface
      [6/11] Verificar conectividade real dentro da VM (DNS + TCP)
      [7/11] Copiar e executar Prepare-RealisticEnvironment.ps1
      [8/11] Validar estado (JSON + flag no guest)
      [9/11] Parar VM + remover adaptador externo (isolamento forçado)
     [10/11] Confirmar isolamento: arrancar VM e verificar que DNS público falha
     [11/11] Parar VM, criar/atualizar snapshot CleanState

    O snapshot final contém:
      - Windows com software instalado (7-Zip, Notepad++, Chrome, Acrobat, VLC)
      - Ambiente "realista" (ficheiros isca, UAC off, SmartScreen off)
      - SEM qualquer adaptador externo — só SandboxSwitch (Internal)
      - Garantia de isolamento total da internet

.PARAMETER AllowWithoutWinget
    Permite concluir sem winget (laboratório sem App Installer). Não recomendado.
.PARAMETER ExternalSwitchName
    Nome do switch externo a usar para internet. Se omitido, usa o primeiro External disponível
    ou cria automaticamente um a partir de -PreferredNetAdapterName.
.PARAMETER PreferredNetAdapterName
    Adaptador físico do host a usar se for necessário criar um switch externo. Predefinição: "Wi-Fi".
.PARAMETER AutoExternalSwitchName
    Nome do switch externo criado automaticamente. Predefinição: "ExternalWiFi".
.PARAMETER SkipConnectivityCheck
    Não verifica conectividade antes de instalar (útil se o teste de DNS falhar por outro motivo).
.EXAMPLE
    .\05-FirstTimeVmSetup.ps1
    .\05-FirstTimeVmSetup.ps1 -ExternalSwitchName "Default Switch"
    .\05-FirstTimeVmSetup.ps1 -AllowWithoutWinget -SkipConnectivityCheck
#>
#Requires -RunAsAdministrator

param(
    [switch] $AllowWithoutWinget,
    [string] $ExternalSwitchName      = "",
    [string] $PreferredNetAdapterName = "Wi-Fi",
    [string] $AutoExternalSwitchName  = "ExternalWiFi",
    [switch] $SkipConnectivityCheck
)

$ErrorActionPreference = "Stop"

$scriptRoot   = $PSScriptRoot
$configScript = Join-Path $scriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName          = $script:PROJETOVM_VMName
$SnapshotName    = $script:PROJETOVM_SnapshotName
$SandboxSwitch   = $script:PROJETOVM_SwitchName
$VMScriptsPath   = "C:\analysis_work"
$GuestUser       = $script:PROJETOVM_GuestUser
$GuestPassword   = $script:PROJETOVM_GuestPassword
$TempAdapterName = "TempInternet"

Import-Module (Join-Path $scriptRoot "SandboxCommon.psm1") -ErrorAction Stop

# ---------------------------------------------------------------------------
# Helpers de conectividade
# ---------------------------------------------------------------------------
function Test-TcpPort {
    param([string]$TargetHost = "8.8.8.8", [int]$Port = 53, [int]$TimeoutMs = 3000)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Test-DnsPublic {
    param([string]$Hostname = "example.com")
    try { $null = [System.Net.Dns]::GetHostAddresses($Hostname); return $true }
    catch { return $false }
}

# Helper: limpar e abortar em caso de erro
function Abort-WithCleanup {
    param([string] $Reason)
    Write-LogHost "[ERRO] $Reason"
    Write-LogHost "       A parar VM e remover adaptador de internet por segurança..."
    try { Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 4
    try { Remove-SandboxInternetAdapter -VMName $VMName -AdapterName $TempAdapterName } catch {}
    exit 1
}

Write-LogHost "=== Primeira entrada: internet temporária -> instalação -> isolamento real -> snapshot ==="
Write-LogHost ""

# ---------------------------------------------------------------------------
# Pré-verificações
# ---------------------------------------------------------------------------
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-LogHost "[ERRO] VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1."
    exit 1
}

$prepareScript = Join-Path $scriptRoot "vm\Prepare-RealisticEnvironment.ps1"
if (-not (Test-Path $prepareScript)) {
    Write-LogHost "[ERRO] Script não encontrado: $prepareScript"
    Write-LogHost "       Certifique-se de que o ficheiro vm\Prepare-RealisticEnvironment.ps1 existe."
    exit 1
}

$secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
$cred   = [pscredential]::new($GuestUser, $secure)

# ---------------------------------------------------------------------------
# [1/11] Parar VM para estado limpo
# ---------------------------------------------------------------------------
Write-LogHost "[1/11] A parar a VM (estado limpo)..."
if ($vm.State -ne "Off") {
    Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 6
}
Write-LogHost "       VM desligada."

# ---------------------------------------------------------------------------
# [2/11] Garantir switch externo + adicionar adaptador temporário
# ---------------------------------------------------------------------------
Write-LogHost "[2/11] A configurar adaptador de internet temporário..."

$chosenSwitchName = $ExternalSwitchName

if ([string]::IsNullOrWhiteSpace($chosenSwitchName)) {
    $existingExternal = @(Get-VMSwitch -ErrorAction SilentlyContinue |
        Where-Object { $_.SwitchType -eq "External" -or $_.Name -eq "Default Switch" })

    if ($existingExternal.Count -eq 0) {
        # Tentar criar switch externo automaticamente
        $na = Get-NetAdapter -Name $PreferredNetAdapterName -ErrorAction SilentlyContinue
        if (-not $na -or $na.Status -ne "Up") {
            $na = Get-NetAdapter -ErrorAction SilentlyContinue |
                  Where-Object {
                      $_.Status -eq "Up" -and
                      $_.InterfaceDescription -notlike "*Hyper-V*" -and
                      $_.InterfaceDescription -notlike "*Virtual*"
                  } | Select-Object -First 1
        }

        if ($na) {
            $existingAuto = Get-VMSwitch -Name $AutoExternalSwitchName -ErrorAction SilentlyContinue
            if (-not $existingAuto) {
                Write-LogHost "       Nenhum switch External. A criar '$AutoExternalSwitchName' em '$($na.Name)'..."
                try {
                    New-VMSwitch -Name $AutoExternalSwitchName -NetAdapterName $na.Name `
                        -AllowManagementOS $true -ErrorAction Stop | Out-Null
                    Write-LogHost "       Switch '$AutoExternalSwitchName' criado."
                } catch {
                    Write-LogHost "       AVISO: falha ao criar switch externo: $($_.Exception.Message)"
                }
            }
            $chosenSwitchName = $AutoExternalSwitchName
        } else {
            Write-LogHost "       AVISO: nenhum adaptador físico Up encontrado para criar switch externo."
        }
    } else {
        $sw = $existingExternal |
              Sort-Object @{E={if ($_.SwitchType -eq "External") {0} else {1}}} |
              Select-Object -First 1
        $chosenSwitchName = $sw.Name
        Write-LogHost "       Switch externo encontrado: '$chosenSwitchName'"
    }
}

$usedSwitch = Add-SandboxInternetAdapter `
    -VMName          $VMName `
    -ExternalSwitchName $chosenSwitchName `
    -AdapterName     $TempAdapterName `
    -ExcludeSwitchName $SandboxSwitch

if ($usedSwitch) {
    Write-LogHost "       Internet ativa via switch '$usedSwitch' (adaptador '$TempAdapterName')."
} else {
    Write-LogHost "       AVISO: nenhum switch externo disponível. A prosseguir sem internet."
    if (-not $AllowWithoutWinget) {
        Write-LogHost "       Use -AllowWithoutWinget se quiser continuar sem internet/winget."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# [3/11] Verificar conectividade real do HOST
# ---------------------------------------------------------------------------
Write-LogHost "[3/11] A verificar conectividade do host..."

if ($SkipConnectivityCheck) {
    Write-LogHost "       -SkipConnectivityCheck activo. A saltar."
} else {
    $hostDns = Test-DnsPublic
    $hostTcp = Test-TcpPort

    if (-not $hostDns -and -not $hostTcp) {
        Write-LogHost "       AVISO: HOST sem internet (DNS=$hostDns TCP=$hostTcp)."
        Write-LogHost "       A VM também não terá internet mesmo com o adaptador externo."
        if (-not $AllowWithoutWinget) {
            Abort-WithCleanup "Host sem internet. Use -SkipConnectivityCheck ou corrija a ligação de rede."
        }
        Write-LogHost "       AllowWithoutWinget=true. A continuar."
    } else {
        Write-LogHost "       Host tem internet (DNS=$hostDns TCP=$hostTcp). OK."
    }
}

# ---------------------------------------------------------------------------
# [4/11] Arrancar VM + aguardar PowerShell Direct
# ---------------------------------------------------------------------------
Write-LogHost "[4/11] A arrancar VM e aguardar PowerShell Direct..."
Start-SandboxVM -VMName $VMName -Credential $cred -PowerShellDirectTimeoutSeconds 0

Write-LogHost "       A configurar rede e aceitar popups automaticamente..."

$autoAcceptScript = @'
try {
    # Definir redes como Privada (evita popup de descoberta)
    $netProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($profile in $netProfiles) {
        if ($profile -and $profile.NetworkCategory -ne "Private") {
            Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
            Write-Host "Rede $($profile.Name) definida como Privada"
        }
    }

    # Desativar popup NLA permanentemente
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /v NewNetworkWindowOff /t REG_DWORD /d 1 /f | Out-Null

    # Desativar Windows Welcome / consumer features
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f | Out-Null

    # Marcar OOBE como concluído (reduz prompts)
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f | Out-Null
} catch { Write-Host "Erro: $_" }
'@

try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock ([scriptblock]::Create($autoAcceptScript))
    Write-LogHost "       Configuração automática de rede aplicada."
} catch {
    Write-LogWarning "       Não foi possível configurar rede automaticamente: $_"
}

Start-Sleep -Seconds 5

# ---------------------------------------------------------------------------
# [5/11] Ativar Guest Service Interface
# ---------------------------------------------------------------------------
Write-LogHost "[5/11] A ativar Guest Service Interface..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 5

# ---------------------------------------------------------------------------
# [6/11] Verificar conectividade real DENTRO da VM
# ---------------------------------------------------------------------------
Write-LogHost "[6/11] A verificar conectividade dentro da VM..."

$null = Start-Sleep -Seconds 10

$vmHasInternet = $false
if ($SkipConnectivityCheck) {
    Write-LogHost "       -SkipConnectivityCheck activo. A assumir internet disponível."
    $vmHasInternet = $true
} else {
    $maxWait = 60
    $waited = 0
    while ($waited -lt $maxWait -and -not $vmHasInternet) {
        try {
            $connOk = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                $dnsOk = $false
                try {
                    $null = Resolve-DnsName "microsoft.com" -ErrorAction Stop
                    $dnsOk = $true
                } catch { }

                $httpOk = $false
                try {
                    $r = Invoke-WebRequest -Uri "http://httpbin.org/status/200" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                    $httpOk = ($r.StatusCode -eq 200)
                } catch { }

                return ($dnsOk -or $httpOk)
            } -ErrorAction SilentlyContinue

            $vmHasInternet = [bool]$connOk
            if ($vmHasInternet) {
                Write-LogHost "       VM tem internet após ${waited}s."
                break
            }
        } catch {
            Write-LogHost "       Erro na verificação: $($_.Exception.Message)"
        }

        Write-LogHost "       Aguardando conectividade... (${waited}s)"
        Start-Sleep -Seconds 5
        $waited += 5
    }

    if (-not $vmHasInternet) {
        Write-LogHost "       AVISO: VM sem internet após ${maxWait}s."
        if (-not $AllowWithoutWinget) {
            Abort-WithCleanup "VM sem internet. Verifique o switch externo e a conectividade do host."
        }
        Write-LogHost "       AllowWithoutWinget=true. A continuar."
    }
}

# ---------------------------------------------------------------------------
# [7/11] Copiar e executar Prepare-RealisticEnvironment.ps1
# ---------------------------------------------------------------------------
$guestScript    = "$VMScriptsPath\Prepare-RealisticEnvironment.ps1"
$stateJsonGuest = "$VMScriptsPath\prepare_winget_state.json"
$readyFlagGuest = "$VMScriptsPath\prepare_winget_ready.flag"

Write-LogHost "[7/11] A copiar Prepare-RealisticEnvironment.ps1 para a VM..."
Copy-SandboxVMFile -VMName $VMName -SourcePath $prepareScript -DestinationPath $guestScript

# Opcional: copiar bundle offline do winget para evitar falhas de download dentro da VM.
# Coloque os ficheiros em: scripts\hyperv-sandbox\offline\winget\
#   - AppInstaller.msixbundle
#   - Microsoft.VCLibs.x64.14.00.Desktop.appx
#   - Microsoft.UI.Xaml.2.8.x64.appx
$offlineWingetHostDir = Join-Path $scriptRoot "offline\winget"
$offlineWingetGuestDir = "$VMScriptsPath\offline\winget"
$useOfflineWinget = $false
if (Test-Path -LiteralPath $offlineWingetHostDir) {
    $offlineFiles = @(
        "AppInstaller.msixbundle",
        "Microsoft.VCLibs.x64.14.00.Desktop.appx",
        "Microsoft.UI.Xaml.2.8.x64.appx"
    )
    $missing = @()
    foreach ($f in $offlineFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $offlineWingetHostDir $f))) { $missing += $f }
    }

    if ($missing.Count -eq 0) {
        Write-LogHost "       Bundle offline do winget encontrado. A copiar para a VM..."
        # Criar diretório na VM primeiro (Copy-VMFile com -CreateFullPath normalmente chega,
        # mas isto melhora diagnósticos e evita falhas intermitentes)
        try {
            Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($Path)
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
            } -ArgumentList $offlineWingetGuestDir -ErrorAction SilentlyContinue
        } catch { }

        foreach ($f in $offlineFiles) {
            $src = Join-Path $offlineWingetHostDir $f
            $dst = "$offlineWingetGuestDir\$f"
            Copy-SandboxVMFile -VMName $VMName -SourcePath $src -DestinationPath $dst
            Write-LogHost "         Copiado: $f"
        }
        # Verificar se os ficheiros chegaram
        $filesOk = $false
        try {
            $filesOk = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($Path, $Files)
                $allExist = $true
                foreach ($f in $Files) {
                    if (-not (Test-Path (Join-Path $Path $f))) {
                        Write-Host "Falta: $f"
                        $allExist = $false
                    }
                }
                return $allExist
            } -ArgumentList $offlineWingetGuestDir, $offlineFiles -ErrorAction SilentlyContinue
        } catch { }

        if ($filesOk) {
            Write-LogHost "       Bundle offline verificado na VM."
            $useOfflineWinget = $true
        } else {
            Write-LogWarning "       Bundle offline incompleto na VM. Winget pode falhar."
        }
    } else {
        Write-LogHost "       AVISO: pasta offline existe mas faltam ficheiros: $($missing -join ', ')"
    }
}

Write-LogHost "       A executar na VM (pode demorar 10-20 minutos)..."

try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($Path, $AllowW, $UseOffline, $OfflinePath)
        if (-not (Test-Path $Path)) { throw "Ficheiro não encontrado na VM: $Path" }
        if ($AllowW) {
            if ($UseOffline) {
                & $Path -InstallCommonSoftware -AllowWithoutWinget -OfflineWingetPath $OfflinePath
            } else {
                & $Path -InstallCommonSoftware -AllowWithoutWinget
            }
        } else {
            if ($UseOffline) {
                & $Path -InstallCommonSoftware -OfflineWingetPath $OfflinePath
            } else {
                & $Path -InstallCommonSoftware
            }
        }
    } -ArgumentList $guestScript, $AllowWithoutWinget.IsPresent, $useOfflineWinget, $offlineWingetGuestDir -ErrorAction Stop
} catch {
    Abort-WithCleanup "Preparação na VM falhou: $($_)"
}

Write-LogHost "       A aguardar conclusão da instalação dos pacotes..."

# Aguardar até 10 minutos pela conclusão do winget (se estiver em execução)
$maxWaitSeconds = 600
$waited = 0
$interval = 10

while ($waited -lt $maxWaitSeconds) {
    try {
        $wingetRunning = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            $proc = Get-Process winget -ErrorAction SilentlyContinue
            return ($null -ne $proc)
        } -ErrorAction SilentlyContinue

        if (-not $wingetRunning) {
            Write-LogHost "       Winget concluído após ${waited}s."
            break
        }
    } catch { }

    Start-Sleep -Seconds $interval
    $waited += $interval
    Write-LogHost "       Aguardando winget... (${waited}s)"
}

# ---------------------------------------------------------------------------
# [8/11] Validar estado no guest (JSON + flag)
# ---------------------------------------------------------------------------
Write-LogHost "[8/11] A validar estado pós-instalação..."

try {
    $stateGuest = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($JsonPath, $FlagPath)
        $r = @{ ok = $false; reason = "missing_json"; allVerified = $false
                wingetFound = $false; readyFlag = $false; packages = @() }
        if (-not (Test-Path $JsonPath)) { return $r }
        try {
            $o = (Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
            $r.allVerified = [bool]$o.allVerified
            $r.wingetFound = [bool]$o.wingetFound
            $r.packages    = $o.packages
            $r.ok          = [bool]$o.allVerified
            $r.reason      = if ($r.ok) { "ok" } else { "allVerified_false" }
        } catch {
            $r.reason = "json_parse_error: $($_.Exception.Message)"
        }
        $r.readyFlag = Test-Path -LiteralPath $FlagPath
        return $r
    } -ArgumentList $stateJsonGuest, $readyFlagGuest -ErrorAction Stop
} catch {
    Abort-WithCleanup "Não foi possível ler o estado na VM: $_"
}

Write-LogHost "       allVerified=$($stateGuest.allVerified)  wingetFound=$($stateGuest.wingetFound)  readyFlag=$($stateGuest.readyFlag)"
if ($stateGuest.packages) {
    foreach ($p in $stateGuest.packages) {
        $ico = if ($p.verified) { "[OK]    " } else { "[FALHOU]" }
        Write-LogHost "         $ico $($p.friendlyName)"
    }
}

if (-not $stateGuest.ok) {
    Abort-WithCleanup "allVerified=false (reason: $($stateGuest.reason)). Corrija e reexecute."
}

# ---------------------------------------------------------------------------
# [9/11] Parar VM + remover TODOS os adaptadores externos (isolamento forçado)
# ---------------------------------------------------------------------------
Write-LogHost "[9/11] A parar VM e cortar internet (isolamento forçado)..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 6

# Remover o adaptador temporário pelo nome
Remove-SandboxInternetAdapter -VMName $VMName -AdapterName $TempAdapterName

# Verificação extra: remover qualquer adaptador ligado a switch não-Internal
$allAdapters = @(Get-VMNetworkAdapter -VMName $VMName)
foreach ($adapter in $allAdapters) {
    if ([string]::IsNullOrWhiteSpace($adapter.SwitchName)) { continue }
    $sw = Get-VMSwitch -Name $adapter.SwitchName -ErrorAction SilentlyContinue
    if ($sw -and $sw.SwitchType -ne "Internal") {
        Write-LogHost "       Adaptador '$($adapter.Name)' ligado a switch não-Internal '$($adapter.SwitchName)' (tipo: $($sw.SwitchType)). A remover..."
        try {
            Remove-VMNetworkAdapter -VMName $VMName -Name $adapter.Name -ErrorAction Stop | Out-Null
            Write-LogHost "       Removido."
        } catch {
            Write-LogHost "[ERRO] Não foi possível remover '$($adapter.Name)': $($_.Exception.Message)"
            exit 1
        }
    }
}

# Confirmação final: o adaptador TempInternet não pode existir
if (Test-SandboxInternetAdapterExists -VMName $VMName -AdapterName $TempAdapterName) {
    Write-LogHost "[ERRO CRÍTICO] Adaptador '$TempAdapterName' ainda presente. A abortar."
    exit 1
}

Write-LogHost "       Adaptadores restantes (devem ser apenas SandboxSwitch/Internal):"
Get-VMNetworkAdapter -VMName $VMName | ForEach-Object {
    $swType = ((Get-VMSwitch -Name $_.SwitchName -ErrorAction SilentlyContinue).SwitchType)
    Write-LogHost "         - $($_.Name) -> '$($_.SwitchName)' [$swType]"
}

# ---------------------------------------------------------------------------
# [10/11] Arrancar VM e confirmar isolamento real
# ---------------------------------------------------------------------------
Write-LogHost "[10/11] A confirmar isolamento (arrancar VM, testar DNS público)..."
Start-SandboxVM -VMName $VMName -Credential $cred -PowerShellDirectTimeoutSeconds 0

try {
    $isoResult = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        $dns = $false
        try { $null = [System.Net.Dns]::GetHostAddresses("example.com"); $dns = $true } catch {}
        $tcp = $false
        try {
            $c  = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect("8.8.8.8", 53, $null, $null)
            $tcp = $ar.AsyncWaitHandle.WaitOne(3000, $false)
            $c.Close()
        } catch {}
        return @{ dns = $dns; tcp = $tcp }
    } -ErrorAction SilentlyContinue

    if ($isoResult -and ($isoResult.dns -or $isoResult.tcp)) {
        Write-LogHost "       [AVISO] VM ainda tem acesso à internet! DNS=$($isoResult.dns) TCP=$($isoResult.tcp)"
        Write-LogHost "               Verifique se o SandboxSwitch ($SandboxSwitch) é Internal"
        Write-LogHost "               e se não existe NAT configurado no host para 192.168.100.0/24."
        Write-LogHost "               A prosseguir com snapshot (corrija o isolamento manualmente se necessário)."
    } else {
        Write-LogHost "       ISOLAMENTO CONFIRMADO: DNS e TCP para internet falharam dentro da VM."
    }
} catch {
    Write-LogHost "       Verificação de isolamento inconclusiva: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# [11/11] Parar VM e criar snapshot CleanState
# ---------------------------------------------------------------------------
Write-LogHost "[11/11] A parar VM e criar snapshot '$SnapshotName'..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8

$existing = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if ($existing) {
    Write-LogHost "        A remover snapshot anterior '$SnapshotName'..."
    Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "        Snapshot '$SnapshotName' criado com sucesso."

Disable-SandboxGuestService -VMName $VMName

Write-LogHost ""
Write-LogHost "=== Primeira entrada concluída com sucesso. ==="
Write-LogHost ""
Write-LogHost "    Software instalado (internet temporária, agora cortada):"
Write-LogHost "      7-Zip, Notepad++, Google Chrome, Adobe Acrobat Reader, VLC"
Write-LogHost "    Internet: REMOVIDA (sem adaptadores externos na VM)"
Write-LogHost "    Snapshot '$SnapshotName': CRIADO (VM desligada, isolamento confirmado)"
Write-LogHost ""
Write-LogHost "    Próximo passo: .\04-Run-Sample.ps1 -SamplePath <caminho>"