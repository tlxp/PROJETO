# --- Script: _Config.ps1 ---
<#
.SYNOPSIS
    Configuração central do sandbox Hyper-V. Todas as pastas usam D:\PROJETOVM.
.DESCRIPTION
    - VMMemoryStartupMB: 0 = auto (25% RAM host, entre 2-4 GB)
    - VMProcessorCount : 0 = auto (metade dos núcleos lógicos, min 1)
    - VMGeneration     : 1 = BIOS/Legacy (recomendado se Gen2 falhar boot ISO)
                         2 = UEFI (requer ISO com El Torito UEFI válido)
#>

# --- Pasta raiz do ambiente ---
# *Sobreponível via variável de ambiente PROJETOVM_BasePath*
$script:PROJETOVM_BasePath = if ($env:PROJETOVM_BasePath) { $env:PROJETOVM_BasePath } else { "D:\PROJETOVM" }

# --- Identificação da VM e rede ---
$script:PROJETOVM_VMName        = "MalwareSandbox"
$script:PROJETOVM_SnapshotName  = "CleanState"
$script:PROJETOVM_SwitchName    = "SandboxSwitch"
$script:PROJETOVM_VMGeneration  = 1      # 1 = Gen1 (BIOS), 2 = Gen2 (UEFI)

# --- Recursos de hardware (0 = auto) ---
$script:PROJETOVM_VMMemoryStartupMB   = 0       # 0 = auto
$script:PROJETOVM_VMProcessorCount    = 0       # 0 = auto
$script:PROJETOVM_VHDSizeGB           = 80
$script:PROJETOVM_DynamicMemoryEnabled = $true

# --- Instalação Windows unattended ---
# *Apenas en-US suportado para autounattend*
$script:PROJETOVM_WindowsIsoPath      = "D:\ISOs\Windows.iso"
$script:PROJETOVM_AutoInstallWindows  = $true

# --- Credenciais do guest ---
$script:PROJETOVM_GuestUser = if ($env:PROJETOVM_GuestUser) { $env:PROJETOVM_GuestUser } else { "analyst" }
if ($env:PROJETOVM_GuestPassword) {
    $script:PROJETOVM_GuestPassword = $env:PROJETOVM_GuestPassword
} elseif ($env:PROJETOVM_ALLOW_INSECURE_DEFAULTS -eq '1') {
    $script:PROJETOVM_GuestPassword = "Analyst123!"
    Write-Warning "[PROJETOVM] PROJETOVM_ALLOW_INSECURE_DEFAULTS=1 - password de exemplo em uso. Nao use em producao."
} else {
    throw "[PROJETOVM] PROJETOVM_GuestPassword nao definida. Defina a variavel de ambiente ou, apenas em dev, PROJETOVM_ALLOW_INSECURE_DEFAULTS=1."
}

# --- Pastas derivadas (calculadas a partir de BasePath) ---
$script:PROJETOVM_VMPath      = Join-Path $script:PROJETOVM_BasePath "VM"
$script:PROJETOVM_ReportsPath = Join-Path $script:PROJETOVM_BasePath "Reports"
$script:PROJETOVM_SamplesPath = Join-Path $script:PROJETOVM_BasePath "Samples"
$script:PROJETOVM_LogsPath    = Join-Path $script:PROJETOVM_BasePath "Logs"

# --- Comunicação host<->guest via COM1/pipe ---
# *O script 04-Run-Sample acrescenta _<RunId> por execução*
$script:PROJETOVM_PipeName = "SandboxReportPipe"

# --- Timeouts e transferência de ficheiros ---
$script:PROJETOVM_PowerShellDirectTimeoutSeconds = 240
$script:PROJETOVM_UseGuestServices = $false
$script:PROJETOVM_PsDirectChunkSizeBytes = 2097152
$script:PROJETOVM_PipeIdleReconnectSec = 900

# --- Auto-detecção de recursos do host ---
function Get-ProjetoVMResourceDefaults {
    $cs          = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $totalBytes  = if ($cs) { $cs.TotalPhysicalMemory } else { 8GB }
    $logicalProcs = if ($cs) { $cs.NumberOfLogicalProcessors } else { 2 }
    $totalGB     = [math]::Round($totalBytes / 1GB, 2)
    # *25% da RAM do host, limitado entre 2-4 GB*
    $memMB       = [int]([math]::Min(4096, [math]::Max(2048, ($totalBytes * 0.25) / 1MB)))
    if (($memMB % 2) -ne 0) { $memMB-- }
    $procCount   = [int][math]::Min(2, [math]::Max(1, [math]::Floor($logicalProcs / 2)))
    return @{ MemoryMB = $memMB; ProcessorCount = $procCount; HostRAMGB = $totalGB; HostLogicalProcs = $logicalProcs }
}

# --- Exportação da configuração como objeto ---
function Get-ProjetoVMConfig {
    [PSCustomObject]@{
        BasePath             = $script:PROJETOVM_BasePath
        VMPath               = $script:PROJETOVM_VMPath
        ReportsPath          = $script:PROJETOVM_ReportsPath
        SamplesPath          = $script:PROJETOVM_SamplesPath
        LogsPath             = $script:PROJETOVM_LogsPath
        VMName               = $script:PROJETOVM_VMName
        SnapshotName         = $script:PROJETOVM_SnapshotName
        SwitchName           = $script:PROJETOVM_SwitchName
        VMGeneration         = $script:PROJETOVM_VMGeneration
        VMMemoryStartupMB    = $script:PROJETOVM_VMMemoryStartupMB
        VMProcessorCount     = $script:PROJETOVM_VMProcessorCount
        VHDSizeGB            = $script:PROJETOVM_VHDSizeGB
        DynamicMemoryEnabled = $script:PROJETOVM_DynamicMemoryEnabled
        WindowsIsoPath       = $script:PROJETOVM_WindowsIsoPath
        AutoInstallWindows   = $script:PROJETOVM_AutoInstallWindows
        GuestUser            = $script:PROJETOVM_GuestUser
        GuestPassword        = $script:PROJETOVM_GuestPassword
        PipeName             = $script:PROJETOVM_PipeName
        PowerShellDirectTimeoutSeconds = $script:PROJETOVM_PowerShellDirectTimeoutSeconds
        UseGuestServices             = $script:PROJETOVM_UseGuestServices
    }
}
