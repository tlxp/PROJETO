# --- Script: PhaseD-CopyInstall.ps1 ---

# --- Preparação da pasta de instaladores na VM ---
$vmInstallDir = "C:\analysis_work\installers"
try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($Dir)
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    } -ArgumentList $vmInstallDir -ErrorAction Stop | Out-Null
} catch {
    Write-LogWarning "Não foi possível preparar '$vmInstallDir' na VM: $($_.Exception.Message)"
}

# --- Cópia de instaladores para a VM ---
Write-LogHost ""
Write-LogHost "A copiar instaladores para a VM..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 2

foreach ($it in $resolved) {
    $dst = Join-Path $vmInstallDir $it.File
    Write-LogHost ("  [COPY] {0} -> {1}" -f $it.File, $dst)
    Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $it.HostPath -DestinationPath $dst
}

# --- Instalação silenciosa na VM ---
Write-LogHost ""
Write-LogHost "A instalar na VM (silencioso)..."
foreach ($it in $resolved) {
    $dst = Join-Path $vmInstallDir $it.File
    Write-LogHost ("  [RUN]  {0}" -f $it.Name)
    try {
        $res = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($PathExe, $InstallerArgs)
            if (-not (Test-Path -LiteralPath $PathExe)) { return @{ ok = $false; code = -1; msg = "instalador ausente" } }
            $p = Start-Process -FilePath $PathExe -ArgumentList $InstallerArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
            if (-not $p) { return @{ ok = $false; code = -2; msg = "falha ao iniciar" } }
            return @{ ok = $true; code = [int]$p.ExitCode; msg = "ok" }
        } -ArgumentList $dst, $it.Args -ErrorAction Stop

        # *ExitCode 0 = sucesso; 3010 = sucesso com reinício pendente.*
        $code = if ($res -and $res.code -ne $null) { [int]$res.code } else { 0 }
        if ($code -eq 0 -or $code -eq 3010) {
            Write-LogHost ("        OK (ExitCode={0})" -f $code)
        } else {
            Write-LogWarning ("        ExitCode={0} (pode requerer atenção)" -f $code)
        }
    } catch {
        Write-LogWarning ("        Erro ao instalar: {0}" -f $_.Exception.Message)
    }
}
