# Instalar Sysmon antes do snapshot CleanState (telemetria primária da análise).
Write-LogHost ""
Write-LogHost "       A instalar Sysmon na VM (persistido no snapshot CleanState)..."

$InstallSysmonLibDir = Join-Path $scriptRoot 'InstallSysmon'
. (Join-Path $InstallSysmonLibDir 'SysmonResolve.ps1')
. (Join-Path $InstallSysmonLibDir 'Install-SysmonInGuestCore.ps1')

try {
    Install-SysmonInSandboxGuest -VMName $VMName -Credential $cred -SkipIfAlreadyInstalled
    Write-LogHost "       Sysmon operacional; será incluído no snapshot '$SnapshotName'."
} catch {
    Write-LogWarning "       Falha ao instalar Sysmon: $($_.Exception.Message)"
    Write-LogWarning "       Execute depois: .\03-Install-SysmonInGuest.ps1 -UpdateCleanSnapshot"
    Abort-WithCleanup "Sysmon é obrigatório para análise comportamental de alta fidelidade."
}
