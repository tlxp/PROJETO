# --- Módulo: SandboxCommon.psm1 ---
# --- Módulo partilhado do sandbox Hyper-V ---
param(
    [switch] $DryRun
)

$script:SandboxGuestFileCopyMode = $null

# --- Carregamento modular das funções partilhadas ---
# As funções estão organizadas em ficheiros temáticos dentro de .\SandboxCommon\.
# São carregadas via dot-sourcing (mesma scope do módulo), partilhando $script:DryRun.
$script:SandboxCommonPartsDir = Join-Path $PSScriptRoot 'SandboxCommon'
$sandboxCommonParts = @(
    'Logging.ps1',         # Get-LogTimestamp, Write-LogHost, Write-LogWarning, Write-SandboxLog, Write-SandboxJsonLog
    'Hashing.ps1',         # Assert-FileSha1
    'IsoUnattend.ps1',     # ISO / autounattend.xml / VHDX / idiomas
    'VmReadiness.ps1',     # Heartbeat, credenciais, PowerShell Direct, Guest Service
    'HostSetup.ps1',       # Diretórios, pré-requisitos, VMSwitch, rede do host
    'VmStart.ps1',         # Arranque da VM (com fallback de RAM) e Guest Service ready
    'SerialPipe.ps1',      # Canal serial COM1 <-> Named Pipe (relatório)
    'VmFileTransfer.ps1'   # Cópia host<->guest, snapshot, stop, verificações no guest
)
foreach ($part in $sandboxCommonParts) {
    . (Join-Path $script:SandboxCommonPartsDir $part)
}

Export-ModuleMember -Function * -Variable DryRun
