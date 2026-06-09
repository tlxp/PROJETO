# [3/5] Ativar Guest Service Interface
Write-LogHost "[3/5] A ativar Guest Service Interface..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 1
