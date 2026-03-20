<#
.SYNOPSIS
    Configuracao central do sandbox Hyper-V. Todas as pastas usam D:\PROJETOVM.
.DESCRIPTION
    - VMMemoryStartupMB: 0 = auto (25% RAM host, entre 1-4 GB)
    - VMProcessorCount : 0 = auto (metade dos nucleos logicos, min 1)
    - VMGeneration     : 1 = BIOS/Legacy (recomendado se Gen2 falhar boot ISO)
                         2 = UEFI (requer ISO com El Torito UEFI valido)
#>

# Pasta raiz
$script:PROJETOVM_BasePath = "D:\PROJETOVM"

# VM
$script:PROJETOVM_VMName        = "MalwareSandbox"
$script:PROJETOVM_SnapshotName  = "CleanState"
$script:PROJETOVM_SwitchName    = "SandboxSwitch"
$script:PROJETOVM_PipeName      = "SandboxReportPipe"
$script:PROJETOVM_VMGeneration  = 1      # <-- 1 = Gen1 (BIOS), 2 = Gen2 (UEFI)

# Recursos (0 = auto)
$script:PROJETOVM_VMMemoryStartupMB   = 0       # 0 = auto
$script:PROJETOVM_VMProcessorCount    = 0       # 0 = auto
$script:PROJETOVM_VHDSizeGB           = 80
$script:PROJETOVM_DynamicMemoryEnabled = $true

# ISO do Windows (sem verificacao SHA-1)
$script:PROJETOVM_WindowsIsoPath      = "D:\ISOs\Windows.iso"
$script:PROJETOVM_AutoInstallWindows  = $true

# Utilizador criado pela instalacao unattended
$script:PROJETOVM_GuestUser     = "analyst"
$script:PROJETOVM_GuestPassword = "Analyst123!"

# Pastas derivadas (nao editar)
$script:PROJETOVM_VMPath      = Join-Path $script:PROJETOVM_BasePath "VM"
$script:PROJETOVM_ReportsPath = Join-Path $script:PROJETOVM_BasePath "Reports"
$script:PROJETOVM_SamplesPath = Join-Path $script:PROJETOVM_BasePath "Samples"
$script:PROJETOVM_LogsPath    = Join-Path $script:PROJETOVM_BasePath "Logs"

function Get-ProjetoVMResourceDefaults {
    $cs          = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $totalBytes  = if ($cs) { $cs.TotalPhysicalMemory } else { 8GB }
    $logicalProcs = if ($cs) { $cs.NumberOfLogicalProcessors } else { 2 }
    $totalGB     = [math]::Round($totalBytes / 1GB, 2)
    $memMB       = [int]([math]::Min(4096, [math]::Max(1024, ($totalBytes * 0.25) / 1MB)))
    if (($memMB % 2) -ne 0) { $memMB-- }
    $procCount   = [int][math]::Min(2, [math]::Max(1, [math]::Floor($logicalProcs / 2)))
    return @{ MemoryMB = $memMB; ProcessorCount = $procCount; HostRAMGB = $totalGB; HostLogicalProcs = $logicalProcs }
}

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
        PipeName             = $script:PROJETOVM_PipeName
        VMGeneration         = $script:PROJETOVM_VMGeneration
        VMMemoryStartupMB    = $script:PROJETOVM_VMMemoryStartupMB
        VMProcessorCount     = $script:PROJETOVM_VMProcessorCount
        VHDSizeGB            = $script:PROJETOVM_VHDSizeGB
        DynamicMemoryEnabled = $script:PROJETOVM_DynamicMemoryEnabled
        WindowsIsoPath       = $script:PROJETOVM_WindowsIsoPath
        AutoInstallWindows   = $script:PROJETOVM_AutoInstallWindows
        GuestUser            = $script:PROJETOVM_GuestUser
    }
}