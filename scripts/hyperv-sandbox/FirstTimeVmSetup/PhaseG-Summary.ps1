# Resumo final
Write-LogHost ""
Write-LogHost "=========================================================="
Write-LogHost "=== Primeira entrada concluida com sucesso. ==="
Write-LogHost "=========================================================="
Write-LogHost ""
Write-LogHost '    Internet:             REMOVIDA (sem adaptadores externos na VM)'
Write-LogHost ('    Snapshot {0}: CRIADO (VM desligada, isolamento confirmado)' -f $SnapshotName)
Write-LogHost ""
# Exemplo abaixo entre aspas simples (evita quebra do parser com maior ou menor nas mensagens).
Write-LogHost '    Proximo passo: .\04-Run-Sample.ps1 -SamplePath C:\caminho\para\amostra.exe'
Write-LogHost ""
