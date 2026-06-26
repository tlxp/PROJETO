# --- Módulo: PhaseB-Boot.ps1 ---
# --- Parar VM, arrancar e aguardar PowerShell Direct ---

# --- [1/5] Parar VM para estado limpo ---
Write-LogHost '[1/5] A parar a VM (estado limpo)...'
if ($vm.State -ne "Off") {
    # Força desligamento para garantir ponto de partida consistente
    Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}
Write-LogHost "       VM desligada."

# --- [2/5] Arrancar VM e aguardar PowerShell Direct ---
Write-LogHost "[2/5] A arrancar VM e aguardar PowerShell Direct..."
try {
    $psDirectOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PowerShellDirectTimeoutSeconds
} catch {
    $psDirectOk = $false
    Write-LogWarning ('       Erro ao aguardar PowerShell Direct: {0}' -f $_.Exception.Message)
}

# --- Validação do PowerShell Direct ---
if (-not $psDirectOk) {
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO] PowerShell Direct não ficou disponível."
    Write-LogHost "Isto normalmente acontece quando:"
    Write-LogHost '  - O utilizador/senha do guest estão errados (ver _Config.ps1: GuestUser/GuestPassword)'
    Write-LogHost "  - A VM ainda está em OOBE / não terminou a instalação"
    Write-LogHost ('  - O autounattend.xml não foi aplicado, logo o utilizador ''{0}'' não existe' -f $GuestUser)
    Write-LogHost ""
    Write-LogHost "Checklist rápida:"
    Write-LogHost "  1) Abra a consola da VM no Hyper-V e confirme que entra no Windows."
    Write-LogHost ('  2) Confirme que o utilizador ''{0}'' existe e consegue fazer logon.' -f $GuestUser)
    Write-LogHost '  3) (Opcional) Dentro da VM confirme se existe C:\unattend_applied.txt.'
    Write-LogHost '  4) Se necessário, reexecute 01-Setup-MalwareSandbox.ps1 -ForceReinstall.'
    Write-LogHost "=========================================================="
    Write-LogHost ""
    Abort-WithCleanup "Sem PowerShell Direct (timeout=${PowerShellDirectTimeoutSeconds}s)."
}

# Se Start-SandboxVM devolveu a credencial aceite, reutilizá-la no resto do fluxo
if ($psDirectOk -is [pscredential]) {
    $cred = $psDirectOk
}

# --- Configuração automática de rede e serviços no guest ---
Write-LogHost "       A configurar rede e aceitar popups automaticamente..."

$autoAcceptScript = @'
try {
    # Garantir serviços essenciais (NLA/DHCP/BITS) -- em instalacoes novas podem estar atrasados
    foreach ($svcName in @("NlaSvc","Dhcp","Dnscache","BITS","AppXSvc","StateRepository")) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne "Running") {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
                Write-Host "Serviço iniciado: $svcName"
            }
        } catch { Write-Host "AVISO serviço ${svcName}: $_" }
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

    # Garantir que o serviço AppX esta configurado para início automático
    Set-Service -Name AppXSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppXSvc -ErrorAction SilentlyContinue

    Write-Host "Configuração automática de rede/serviços concluida."
} catch {
    Write-Host "Erro na configuração automática: $_"
}
'@

try {
    # Executa script de configuração remota via PowerShell Direct
    $autoResult = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock ([scriptblock]::Create($autoAcceptScript))
    $autoResult | ForEach-Object { Write-LogHost "         $_" }
    Write-LogHost "       Configuração automática aplicada."
} catch {
    Write-LogWarning "       Não foi possível configurar rede automaticamente: $_"
}

Start-Sleep -Seconds 1
