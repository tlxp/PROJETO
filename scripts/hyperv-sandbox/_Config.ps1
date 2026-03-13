<#
.SYNOPSIS
    Configuração central do sandbox Hyper-V. Todas as pastas e nomes usam D:\PROJETOVM.
.DESCRIPTION
    Parâmetros de VM: use 0 para "auto" (calculado a partir do host).
    - VMMemoryStartupMB: 0 = auto (25% da RAM do host, entre 1–4 GB)
    - VMProcessorCount: 0 = auto (mínimo de 2 e metade dos núcleos lógicos)
#>
# Pasta raiz do projeto (VM, relatórios, amostras)
$script:PROJETOVM_BasePath = "D:\PROJETOVM"

# Nome da VM e do snapshot
$script:PROJETOVM_VMName = "MalwareSandbox"
$script:PROJETOVM_SnapshotName = "CleanState"
$script:PROJETOVM_SwitchName = "SandboxSwitch"
$script:PROJETOVM_PipeName = "SandboxReportPipe"

# Recursos da VM (0 = automático a partir do host)
$script:PROJETOVM_VMMemoryStartupMB = 0    # 0 = auto; ou ex: 2048, 4096
$script:PROJETOVM_VMProcessorCount = 0     # 0 = auto; ou ex: 1, 2
$script:PROJETOVM_VHDSizeGB = 80           # Tamanho do disco virtual em GB
$script:PROJETOVM_DynamicMemoryEnabled = $false

# Instalação automática do Windows (opcional)
$script:PROJETOVM_WindowsIsoPath = "D:\ISOs\Windows.iso"
$script:PROJETOVM_AutoInstallWindows = $true
# Utilizador local criado pela instalação unattended (sandbox)
$script:PROJETOVM_GuestUser = "analyst"
$script:PROJETOVM_GuestPassword = "Analyst123!"

# Pastas derivadas
$script:PROJETOVM_VMPath = Join-Path $script:PROJETOVM_BasePath "VM"
$script:PROJETOVM_ReportsPath = Join-Path $script:PROJETOVM_BasePath "Reports"
$script:PROJETOVM_SamplesPath = Join-Path $script:PROJETOVM_BasePath "Samples"
$script:PROJETOVM_LogsPath = Join-Path $script:PROJETOVM_BasePath "Logs"

function Get-ProjetoVMResourceDefaults {
    <#
    .SYNOPSIS
        Calcula memória e processadores para a VM com base no host (usado quando config = 0).
    #>
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $totalBytes = if ($cs) { $cs.TotalPhysicalMemory } else { 8GB }
    $logicalProcs = if ($cs) { $cs.NumberOfLogicalProcessors } else { 2 }
    $totalGB = [math]::Round($totalBytes / 1GB, 2)
    # RAM: 25% do host, mínimo 1 GB, máximo 4 GB
    $memMB = [int]([math]::Min(4096, [math]::Max(1024, ($totalBytes * 0.25) / 1MB)))
    # Hyper-V exige StartupBytes múltiplo de 2MB
    if (($memMB % 2) -ne 0) { $memMB = $memMB - 1 }
    # CPUs: mínimo 1, máximo min(2, metade dos lógicos)
    $procCount = [int][math]::Min(2, [math]::Max(1, [math]::Floor($logicalProcs / 2)))
    return @{ MemoryMB = $memMB; ProcessorCount = $procCount; HostRAMGB = $totalGB; HostLogicalProcs = $logicalProcs }
}

function Get-ProjetoVMConfig {
    [PSCustomObject]@{
        BasePath   = $script:PROJETOVM_BasePath
        VMPath     = $script:PROJETOVM_VMPath
        ReportsPath = $script:PROJETOVM_ReportsPath
        SamplesPath = $script:PROJETOVM_SamplesPath
        LogsPath   = $script:PROJETOVM_LogsPath
        VMName     = $script:PROJETOVM_VMName
        SnapshotName = $script:PROJETOVM_SnapshotName
        SwitchName = $script:PROJETOVM_SwitchName
        PipeName   = $script:PROJETOVM_PipeName
        VMMemoryStartupMB = $script:PROJETOVM_VMMemoryStartupMB
        VMProcessorCount = $script:PROJETOVM_VMProcessorCount
        VHDSizeGB = $script:PROJETOVM_VHDSizeGB
        DynamicMemoryEnabled = $script:PROJETOVM_DynamicMemoryEnabled
        WindowsIsoPath = $script:PROJETOVM_WindowsIsoPath
        AutoInstallWindows = $script:PROJETOVM_AutoInstallWindows
        GuestUser = $script:PROJETOVM_GuestUser
    }
}
