<#
.SYNOPSIS
    Configuração central do sandbox Hyper-V. Todas as pastas e nomes usam D:\PROJETOVM.
#>
# Pasta raiz do projeto (VM, relatórios, amostras)
$script:PROJETOVM_BasePath = "D:\PROJETOVM"

# Nome da VM e do snapshot
$script:PROJETOVM_VMName = "MalwareSandbox"
$script:PROJETOVM_SnapshotName = "CleanState"
$script:PROJETOVM_SwitchName = "SandboxSwitch"
$script:PROJETOVM_PipeName = "SandboxReportPipe"

# Pastas derivadas
$script:PROJETOVM_VMPath = Join-Path $script:PROJETOVM_BasePath "VM"
$script:PROJETOVM_ReportsPath = Join-Path $script:PROJETOVM_BasePath "Reports"
$script:PROJETOVM_SamplesPath = Join-Path $script:PROJETOVM_BasePath "Samples"
$script:PROJETOVM_LogsPath = Join-Path $script:PROJETOVM_BasePath "Logs"

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
    }
}
