# Criar VM
Write-Host "[5/8] VM $VMName (Gen$VMGeneration, RAM: $memMB MB, CPUs: $procCount, VHD: $vhdSizeGB GB)..."

$existingVm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if ($existingVm) {
    Write-Warning "      A VM '$VMName' ja existe."
    $reinstall = $false
    if ($ForceReinstall) {
        $reinstall = $true
    } else {
        $ans = Read-Host "      Eliminar VM e reinstalar de raiz? (s/N)"
        $reinstall = ($ans -match '^[sS]$')
    }
    if (-not $reinstall) { Write-Host "      Cancelado."; exit 0 }

    Write-Host "      A remover VM e artefatos..."
    if ($existingVm.State -ne "Off") {
        Stop-VM -Name $VMName -TurnOff -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 5
    }
    try { Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
    try { Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
    foreach ($p in @($VHDPath,
                     (Join-Path $VMPath "unattend"),
                     (Join-Path $VMPath "unattend.vfd"),
                     (Join-Path $VMPath "Virtual Machines"),
                     (Join-Path $VMPath "Snapshots"))) {
        if (Test-Path $p) { try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
    }
    $existingVm = $null
    Write-Host "      Remocao concluida."
}

if (-not $existingVm -and (Test-Path $VHDPath)) {
    Write-Warning "      VHDX existente: $VHDPath"
    $delVhd = $false
    if ($ForceReinstall) { $delVhd = $true } else {
        $ans2 = Read-Host "      Eliminar VHDX e criar VM de raiz? (s/N)"
        $delVhd = ($ans2 -match '^[sS]$')
    }
    if (-not $delVhd) { Write-Host "      Cancelado."; exit 0 }
    Remove-Item -LiteralPath $VHDPath -Force -ErrorAction Stop
    Write-Host "      VHDX anterior removido."
}

# Criar VM
New-VM -Name $VMName `
       -MemoryStartupBytes $vmStartupBytes `
       -Generation $VMGeneration `
       -NewVHDPath $VHDPath `
       -NewVHDSizeBytes $vhdSizeBytes `
       -Path $VMPath `
       -SwitchName $SwitchName | Out-Null

Set-VMProcessor -VMName $VMName -Count $procCount | Out-Null

if ($script:PROJETOVM_DynamicMemoryEnabled) {
    Write-Host "      DynamicMemory: ON (Min: $vmMinMB MB, Startup: $vmStartupMB MB, Max: $vmMaxMB MB)"
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -StartupBytes $vmStartupBytes -MinimumBytes $vmMinBytes -MaximumBytes $vmMaxBytes | Out-Null
} else {
    Set-VMMemory -VMName $VMName -StartupBytes $memBytes -DynamicMemoryEnabled $false | Out-Null
}

# Sincronização de tempo (corrige desvio do relógio da VM)
Write-Host "      Enabling Time Synchronization integration service..."
try {
    $timeSvc = Get-VMIntegrationService -VMName $VMName | Where-Object { $_.Name -like "*Time*" -or $_.Name -eq "Time Synchronization" } | Select-Object -First 1
    if ($timeSvc) {
        Enable-VMIntegrationService -VMName $VMName -Name $timeSvc.Name -ErrorAction Stop
        Write-Host "      Time Synchronization enabled."
    } else {
        Write-Warning "      Time Synchronization service not found."
    }
} catch {
    Write-Warning "      Failed to enable Time Synchronization: $_"
}

Write-Host "      VM criada (Generation $VMGeneration)."
