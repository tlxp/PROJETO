# --- Script: PhaseF-Snapshot.ps1 ---
# Fase F: parar VM e criar/atualizar snapshot CleanState.

# --- [5/5] Parar VM e criar snapshot CleanState ---
Write-LogHost ('[5/5] A parar VM e criar snapshot ''{0}''...' -f $SnapshotName)
# *Persiste estado limpo (isolado + Sysmon) como ponto de restauro*
Update-SandboxCleanSnapshot -VMName $VMName -SnapshotName $SnapshotName
