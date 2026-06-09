# Integration Services
Write-Host "[6/8] Integration Services e porta serial..."
Disable-SandboxGuestService -VMName $VMName
$PipeNameSetup = $script:PROJETOVM_PipeName
if ([string]::IsNullOrWhiteSpace($PipeNameSetup)) { $PipeNameSetup = "SandboxReportPipe" }
if ($VMGeneration -eq 1) {
    Set-VMComPort -VMName $VMName -Number 1 -Path "\\.\pipe\$PipeNameSetup" -ErrorAction Stop
    Write-Host "      COM1 -> \\.\pipe\$PipeNameSetup"
} else {
    Write-Host "      Gen2: COM1/pipe não aplicável; o 04 valida Gen1 para relatório por pipe."
}
Write-Host "      Guest Service desativado até à orquestração (policy do sandbox)."
