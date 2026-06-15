# [5/5] Parar VM e criar snapshot CleanState
Write-LogHost ('[5/5] A parar VM e criar snapshot ''{0}''...' -f $SnapshotName)
Update-SandboxCleanSnapshot -VMName $VMName -SnapshotName $SnapshotName
