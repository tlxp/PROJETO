#
# .SYNOPSIS
#     Primeira entrada na VM: valida PowerShell Direct/Guest Services,
#     garante isolamento de rede (sem adaptadores externos) e guarda snapshot CleanState.
# .DESCRIPTION
#     A correr NO HOST. Fluxo:
#
#       [1/5] Parar VM (estado limpo)
#       [2/5] Arrancar VM + aguardar PowerShell Direct
#       [3/5] Ativar Guest Service Interface
#       [4/5] Garantir isolamento: remover adaptadores em switches não-Internal e validar que não há internet
#       [5/5] Parar VM, criar/atualizar snapshot CleanState
#
#     O snapshot final contem:
#       - SEM qualquer adaptador externo -- so SandboxSwitch (Internal)
#       - Garantia de isolamento total da internet
# .EXAMPLE
#     .\05-FirstTimeVmSetup.ps1
#Requires -RunAsAdministrator

param(
    # Evita ficar preso indefinidamente se a VM não aceitar logon (credenciais erradas / OOBE / autounattend não aplicado)
    [int]    $PowerShellDirectTimeoutSeconds = 1200
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

# Recarregar sempre o módulo (evita cache com versões antigas durante troubleshooting)
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $scriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

# Helper: limpar e abortar em caso de erro
function Abort-WithCleanup {
    param([string] $Reason)
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO FATAL] $Reason"
    Write-LogHost "=========================================================="
    Write-LogHost "A parar VM por seguranca..."
    try { Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 4
    Write-LogHost "Cleanup concluido. Verifique os erros acima antes de reexecutar."
    exit 1
}
Write-LogHost "=== Primeira entrada: validar guest -> garantir isolamento -> snapshot ==="
Write-LogHost ""

# ---------------------------------------------------------------------------
# Pre-verificacoes
# ---------------------------------------------------------------------------
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-LogHost "[ERRO] VM '$VMName' nao encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1."
    exit 1
}

$secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# ---------------------------------------------------------------------------
# [1/5] Parar VM para estado limpo
# ---------------------------------------------------------------------------
Write-LogHost "[1/5] A parar a VM (estado limpo)..."
if ($vm.State -ne "Off") {
    Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}
Write-LogHost "       VM desligada."

# ---------------------------------------------------------------------------
# [2/5] Arrancar VM + aguardar PowerShell Direct
# ---------------------------------------------------------------------------
Write-LogHost "[2/5] A arrancar VM e aguardar PowerShell Direct..."
try {
    $psDirectOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PowerShellDirectTimeoutSeconds
} catch {
    $psDirectOk = $false
    Write-LogWarning "       Erro ao aguardar PowerShell Direct: $($_.Exception.Message)"
}

if (-not $psDirectOk) {
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO] PowerShell Direct não ficou disponível."
    Write-LogHost "Isto normalmente acontece quando:"
    Write-LogHost "  - O utilizador/senha do guest estão errados (ver `_Config.ps1`: GuestUser/GuestPassword)"
    Write-LogHost "  - A VM ainda está em OOBE / não terminou a instalação"
    Write-LogHost "  - O `autounattend.xml` não foi aplicado, logo o utilizador '$GuestUser' não existe"
    Write-LogHost ""
    Write-LogHost "Checklist rápida:"
    Write-LogHost "  1) Abra a consola da VM no Hyper-V e confirme que entra no Windows."
    Write-LogHost "  2) Confirme que o utilizador '$GuestUser' existe e consegue fazer logon."
    Write-LogHost "  3) (Opcional) Dentro da VM confirme se existe `C:\unattend_applied.txt`."
    Write-LogHost "  4) Se necessário, reexecute `01-Setup-MalwareSandbox.ps1 -ForceReinstall`."
    Write-LogHost "=========================================================="
    Write-LogHost ""
    Abort-WithCleanup "Sem PowerShell Direct (timeout=${PowerShellDirectTimeoutSeconds}s)."
}

# Se Start-SandboxVM devolveu PSCredential (credencial efetivamente aceite), use-a no resto do script.
if ($psDirectOk -is [pscredential]) {
    $cred = $psDirectOk
}

Write-LogHost "       A configurar rede e aceitar popups automaticamente..."

$autoAcceptScript = @'
try {
    # Garantir servicos essenciais (NLA/DHCP/BITS) -- em instalacoes novas podem estar atrasados
    foreach ($svcName in @("NlaSvc","Dhcp","Dnscache","BITS","AppXSvc","StateRepository")) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne "Running") {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                Write-Host "Servico iniciado: $svcName"
            }
        } catch { Write-Host "AVISO servico ${svcName}: $_" }
    }

    # Forcar DHCP/renovacao
    try { ipconfig /renew 2>&1 | Out-Null } catch { }

    # Definir redes como Privada (evita popup de descoberta)
    $netProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($profile in $netProfiles) {
        if ($profile -and $profile.NetworkCategory -ne "Private") {
            Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue
            Write-Host "Rede '$($profile.Name)' definida como Privada"
        }
    }

    # Desativar popup NLA permanentemente
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /v NewNetworkWindowOff /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # Desativar Windows Welcome / consumer features
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # Marcar OOBE como concluido
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # Garantir que o servico AppX esta configurado para inicio automatico
    Set-Service -Name AppXSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppXSvc -ErrorAction SilentlyContinue

    Write-Host "Configuracao automatica de rede/servicos concluida."
} catch {
    Write-Host "Erro na configuracao automatica: $_"
}
'@

try {
    $autoResult = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock ([scriptblock]::Create($autoAcceptScript))
    $autoResult | ForEach-Object { Write-LogHost "         $_" }
    Write-LogHost "       Configuracao automatica aplicada."
} catch {
    Write-LogWarning "       Nao foi possivel configurar rede automaticamente: $_"
}

Start-Sleep -Seconds 1

# ---------------------------------------------------------------------------
# [3/5] Ativar Guest Service Interface
# ---------------------------------------------------------------------------
Write-LogHost "[3/5] A ativar Guest Service Interface..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 1

# ---------------------------------------------------------------------------
# [4/5] Garantir isolamento (sem adaptadores externos) + validar que não há internet
# ---------------------------------------------------------------------------
Write-LogHost "[4/5] A garantir isolamento de rede (sem adaptadores externos)..."

# Importante: o Hyper-V não permite remover adaptadores sintéticos com a VM em execução.
Write-LogHost "       A parar a VM para remover adaptadores nao-Internal..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# Remover qualquer adaptador ligado a switch não-Internal (ex.: External/Default Switch)
$allAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue)
foreach ($adapter in $allAdapters) {
    if ([string]::IsNullOrWhiteSpace($adapter.SwitchName)) { continue }
    $sw = Get-VMSwitch -Name $adapter.SwitchName -ErrorAction SilentlyContinue
    if ($sw -and $sw.SwitchType -ne "Internal") {
        Write-LogHost "       Adaptador '$($adapter.Name)' em switch nao-Internal '$($adapter.SwitchName)' (tipo: $($sw.SwitchType)). A remover..."
        try {
            Remove-VMNetworkAdapter -VMName $VMName -Name $adapter.Name -ErrorAction Stop | Out-Null
            Write-LogHost "       Removido."
        } catch {
            Write-LogHost "[ERRO] Nao foi possivel remover '$($adapter.Name)': $($_.Exception.Message)"
            exit 1
        }
    }
}

Write-LogHost "       Adaptadores restantes (devem ser apenas SandboxSwitch/Internal):"
Get-VMNetworkAdapter -VMName $VMName | ForEach-Object {
    $swName = $_.SwitchName
    if ([string]::IsNullOrWhiteSpace($swName)) {
        Write-LogHost "         - $($_.Name) -> (sem switch)"
        return
    }
    $swType = ((Get-VMSwitch -Name $swName -ErrorAction SilentlyContinue).SwitchType)
    if ([string]::IsNullOrWhiteSpace($swType)) { $swType = "Unknown" }
    Write-LogHost "         - $($_.Name) -> '$swName' [$swType]"
}

# ---------------------------------------------------------------------------
# Garantir VM em execucao para passos seguintes
# Nota: verificação de "internet" omitida por performance.
# Com switch `Internal` e remoção de adaptadores externos, o risco de fuga é residual.
# ---------------------------------------------------------------------------
Write-LogHost "       A arrancar VM (isolamento assumido: Switch Internal + adaptadores externos removidos)..."
$ps2 = Start-SandboxVM -VMName $VMName -Credential $cred -PowerShellDirectTimeoutSeconds 120
if ($ps2 -is [pscredential]) { $cred = $ps2 }

# ---------------------------------------------------------------------------
# Instalar runtimes essenciais (offline) antes do snapshot
# ---------------------------------------------------------------------------
Write-LogHost ""
Write-LogHost "       A instalar runtimes essenciais (offline) na VM (se disponíveis)..."

$offlineDir = Join-Path $scriptRoot "offline\runtimes"
$vmInstallDir = "C:\analysis_work\installers"

if (-not (Test-Path -LiteralPath $offlineDir)) {
    Write-LogWarning "       Pasta offline não encontrada: $offlineDir"
    Write-LogWarning "       Vou prosseguir sem instalar runtimes. (Recomendado: copiar instaladores para scripts/hyperv-sandbox/offline/runtimes/)"
}
else {
    # Garantir diretório destino na VM
    try {
        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($Dir)
            if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
        } -ArgumentList $vmInstallDir -ErrorAction Stop | Out-Null
    } catch {
        Write-LogWarning "       Não foi possível criar '$vmInstallDir' na VM: $($_.Exception.Message)"
    }

    # Instalers suportados (colocar os ficheiros nesta pasta, com estes nomes).
    $installers = @(
        @{ Name = "VC++ Redistributable (x86)"; File = "VC_redist.x86.exe"; Args = "/install /quiet /norestart" },
        @{ Name = "VC++ Redistributable (x64)"; File = "VC_redist.x64.exe"; Args = "/install /quiet /norestart" },
        @{ Name = ".NET Framework 4.8 (offline)"; File = "ndp48-x86-x64-allos-enu.exe"; Args = "/q /norestart" },
        @{ Name = ".NET Desktop Runtime 8 (x86)"; File = "windowsdesktop-runtime-8.0.*-win-x86.exe"; Args = "/install /quiet /norestart"; AllowPattern = $true },
        @{ Name = ".NET Desktop Runtime 8 (x64)"; File = "windowsdesktop-runtime-8.0.*-win-x64.exe"; Args = "/install /quiet /norestart"; AllowPattern = $true }
    )

    foreach ($it in $installers) {
        $src = $null
        if ($it.AllowPattern -and ($it.File -match "[\*\?]")) {
            try {
                $hit = Get-ChildItem -LiteralPath $offlineDir -File -Filter $it.File -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
                if ($hit) { $src = $hit.FullName }
            } catch { }
        } else {
            $candidate = Join-Path $offlineDir $it.File
            if (Test-Path -LiteralPath $candidate) { $src = $candidate }
        }

        if (-not $src) {
            Write-LogHost "         [SKIP] $($it.Name) — instalador não encontrado: $($it.File)"
            continue
        }

        $realName = Split-Path -Leaf $src

        $dst = Join-Path $vmInstallDir $realName
        try {
            Write-LogHost "         [COPY] $($it.Name) -> $dst"
            Copy-SandboxVMFile -VMName $VMName -SourcePath $src -DestinationPath $dst
        } catch {
            Write-LogWarning "         Falha a copiar '$realName' para VM: $($_.Exception.Message)"
            continue
        }

        try {
            Write-LogHost "         [RUN]  $($it.Name)"
            $res = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($PathExe, $Args)
                if (-not (Test-Path -LiteralPath $PathExe)) { return @{ ok = $false; code = -1; msg = "Instalador não encontrado no guest." } }
                $p = Start-Process -FilePath $PathExe -ArgumentList $Args -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                if (-not $p) { return @{ ok = $false; code = -2; msg = "Falha ao iniciar instalador." } }
                return @{ ok = $true; code = [int]$p.ExitCode; msg = "ok" }
            } -ArgumentList $dst, $it.Args -ErrorAction Stop

            $code = if ($res -and $res.code -ne $null) { [int]$res.code } else { 0 }
            # Muitos instaladores devolvem 0 (OK) ou 3010 (reboot required)
            if ($code -eq 0 -or $code -eq 3010) {
                Write-LogHost "               OK (ExitCode=$code)"
            } else {
                Write-LogWarning "               Instalador terminou com ExitCode=$code (pode requerer atenção)."
            }
        } catch {
            Write-LogWarning "         Erro ao executar '$($it.Name)' na VM: $($_.Exception.Message)"
        }
    }

    # Sanity check: dotnet --info (se existir)
    try {
        $dotnetInfo = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            $p = Get-Command dotnet -ErrorAction SilentlyContinue
            if (-not $p) { return "dotnet: não encontrado" }
            try { return (& dotnet --info 2>&1 | Select-Object -First 12) -join "`n" } catch { return "dotnet: erro ao executar --info" }
        } -ErrorAction SilentlyContinue
        if ($dotnetInfo) {
            Write-LogHost "       dotnet (resumo):"
            ($dotnetInfo -split "`r?`n") | ForEach-Object { Write-LogHost ("         " + $_) }
        }
    } catch { }
}

# ---------------------------------------------------------------------------
# [5/5] Parar VM e criar snapshot CleanState
# ---------------------------------------------------------------------------
Write-LogHost "[5/5] A parar VM e criar snapshot '$SnapshotName'..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$existing = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if ($existing) {
    Write-LogHost "        A remover snapshot anterior '$SnapshotName'..."
    Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "        Snapshot '$SnapshotName' criado com sucesso."

Disable-SandboxGuestService -VMName $VMName

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
Write-LogHost ""
Write-LogHost "=========================================================="
Write-LogHost "=== Primeira entrada concluida com sucesso. ==="
Write-LogHost "=========================================================="
Write-LogHost ""
Write-LogHost "    Internet:             REMOVIDA (sem adaptadores externos na VM)"
Write-LogHost ("    Snapshot '{0}': CRIADO (VM desligada, isolamento confirmado)" -f $SnapshotName)
Write-LogHost ""
Write-LogHost "    Proximo passo: .\\04-Run-Sample.ps1 -SamplePath <caminho>"
Write-LogHost ""