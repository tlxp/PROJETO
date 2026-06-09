# [5/5] Parar VM e criar snapshot CleanState
Write-LogHost ('[5/5] A parar VM e criar snapshot ''{0}''...' -f $SnapshotName)
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$existing = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if ($existing) {
    Write-LogHost ('        A remover snapshot anterior ''{0}''...' -f $SnapshotName)
    Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost ('        Snapshot ''{0}'' criado com sucesso.' -f $SnapshotName)

Disable-SandboxGuestService -VMName $VMName
