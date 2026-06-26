# --- Módulo: Phase9-Summary.ps1 ---
# --- Resumo final e próximos passos ---

# Mensagens finais apresentadas ao operador após conclusão do setup
Write-Host ""
Write-Host "  Concluido."
Write-Host ""
# Estrutura de pastas criada em PROJETOVM
Write-Host "  Estrutura em $BasePath :"
Write-Host "    VM\      -> Sandbox.vhdx e configuração"
Write-Host "    Reports\ -> relatorios de analise"
Write-Host "    Samples\ -> amostras a analisar"
Write-Host "    Logs\    -> logs de execucao"
Write-Host ""
Write-Host "  Proximos passos:"
Write-Host "    1. Dentro da VM: desative rede publica."
Write-Host "       IP estatico opcional: 192.168.100.10/24, gateway 192.168.100.1"
Write-Host "    2. O 04 usa Guest Service so para copias host<->guest; o relatório de texto chega por COM1 -> Named Pipe."
Write-Host "    3. Desligue a VM e atualize o snapshot:"
Write-Host "         Stop-VM -Name $VMName -Force"
Write-Host "         Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName"
Write-Host "    4. Use 04-Run-Sample.ps1 para executar amostras."
Write-Host ""
