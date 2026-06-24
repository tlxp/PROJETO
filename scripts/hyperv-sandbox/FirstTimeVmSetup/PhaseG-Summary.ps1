# --- Script: PhaseG-Summary.ps1 ---
# Fase G: resumo final após conclusão bem-sucedida do first-time setup.

# --- Resumo final ---
Write-LogHost ""
Write-LogHost "=========================================================="
Write-LogHost "=== Primeira entrada concluida com sucesso. ==="
Write-LogHost "=========================================================="
Write-LogHost ""
Write-LogHost '    Internet:             REMOVIDA (sem adaptadores externos na VM)'
Write-LogHost '    Sysmon:               INSTALADO (telemetria primária no guest)'
Write-LogHost ('    Snapshot {0}: CRIADO (VM desligada, isolamento confirmado)' -f $SnapshotName)
Write-LogHost ""
# *Próximo passo sugerido: executar amostra na sandbox*
Write-LogHost '    Proximo passo: .\04-Run-Sample.ps1 -SamplePath C:\caminho\para\amostra.exe'
Write-LogHost ""
