# --- Script: PhaseE2-Sysmon.ps1 ---
# Fase E2: instalar Sysmon no guest (telemetria primária da análise comportamental).

# --- Instalar Sysmon antes do snapshot CleanState ---
Write-LogHost ""
Write-LogHost "       A instalar Sysmon na VM (persistido no snapshot CleanState)..."

# --- Carregar biblioteca de instalação do Sysmon ---
$InstallSysmonLibDir = Join-Path $scriptRoot 'InstallSysmon'
. (Join-Path $InstallSysmonLibDir 'SysmonResolve.ps1')
. (Join-Path $InstallSysmonLibDir 'Install-SysmonInGuestCore.ps1')

try {
    # *Instala Sysmon se ainda não estiver presente no guest*
    Install-SysmonInSandboxGuest -VMName $VMName -Credential $cred -SkipIfAlreadyInstalled
    Write-LogHost "       Sysmon operacional; será incluído no snapshot '$SnapshotName'."
} catch {
    Write-LogWarning "       Falha ao instalar Sysmon: $($_.Exception.Message)"
    Write-LogWarning "       Execute depois: .\03-Install-SysmonInGuest.ps1 -UpdateCleanSnapshot"
    # *Sysmon é obrigatório — aborta com cleanup se a instalação falhar*
    Abort-WithCleanup "Sysmon é obrigatório para análise comportamental de alta fidelidade."
}
