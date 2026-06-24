# --- Script: PhaseC-GuestService.ps1 ---
# Fase C: ativar Guest Service Interface (opcional; não incluída no fluxo principal atual).

# --- [3/5] Ativar Guest Service Interface ---
Write-LogHost "[3/5] A ativar Guest Service Interface..."
# *Habilita integração de serviços de convidado no Hyper-V*
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 1
