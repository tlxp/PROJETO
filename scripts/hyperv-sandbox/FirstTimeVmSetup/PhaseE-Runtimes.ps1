# --- Script: PhaseE-Runtimes.ps1 ---
# Fase E: instalar runtimes essenciais (offline) na VM antes do snapshot.

# --- Instalar runtimes essenciais (offline) ---
Write-LogHost ""
Write-LogHost '       A instalar runtimes essenciais (offline) na VM (se disponíveis)...'

$offlineDir = Join-Path $scriptRoot "offline\runtimes"
$toolsDir = Join-Path $scriptRoot "tools"
$vmInstallDir = "C:\analysis_work\installers"

# --- Staging opcional do WinUtil ---
if ($StageWinutil) {
    try {
        $toolsDir = Join-Path $scriptRoot "tools"
        $winutil = Join-Path $toolsDir "winutil.ps1"
        if (Test-Path -LiteralPath $winutil) {
            Write-LogHost ""
            Write-LogHost "       A copiar WinUtil (staging seguro, sem executar) para a VM..."
            # *Copia WinUtil para a VM sem executar (instalação manual posterior)*
            Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $winutil -DestinationPath "C:\analysis_work\deps\winutil.ps1"
            Write-LogHost "       WinUtil staged em: C:\analysis_work\deps\winutil.ps1"
            Write-LogHost "       Nota: execute manualmente apenas ações de INSTALL no WinUtil."
        } else {
            Write-LogWarning "       StageWinutil pedido, mas não encontrei scripts/hyperv-sandbox/tools/winutil.ps1. Use 06-Prepare-GuestDependencies.ps1 -StageWinutil."
        }
    } catch {
        Write-LogWarning "       Falha ao fazer staging do WinUtil na VM (ignorado): $($_.Exception.Message)"
    }
}

# --- Verificar pastas de instaladores offline ---
if (-not (Test-Path -LiteralPath $offlineDir) -and -not (Test-Path -LiteralPath $toolsDir)) {
    Write-LogWarning ('       Nenhuma pasta de runtimes offline encontrada ({0} ou {1}).' -f $offlineDir, $toolsDir)
    Write-LogWarning '       Vou prosseguir sem instalar runtimes. (Recomendado: scripts/hyperv-sandbox/tools/ ou offline/runtimes/)'
}
else {
    # --- Criar diretório destino na VM ---
    try {
        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($Dir)
            if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
        } -ArgumentList $vmInstallDir -ErrorAction Stop | Out-Null
    } catch {
        Write-LogWarning ('       Não foi possível criar ''{0}'' na VM: {1}' -f $vmInstallDir, $_.Exception.Message)
    }

    # --- Lista de instaladores suportados ---
    $installers = @(
        @{ Name = "VC++ Redistributable (x86)"; File = "VC_redist.x86.exe"; Args = "/install /quiet /norestart" },
        @{ Name = "VC++ Redistributable (x64)"; File = "VC_redist.x64.exe"; Args = "/install /quiet /norestart" },
        @{ Name = ".NET Framework 4.8 (offline)"; File = "ndp48-x86-x64-allos-enu.exe"; Args = "/q /norestart" },
        @{ Name = ".NET Desktop Runtime 8 (x86)"; File = "windowsdesktop-runtime-8.0.*-win-x86.exe"; Args = "/install /quiet /norestart"; AllowPattern = $true },
        @{ Name = ".NET Desktop Runtime 8 (x64)"; File = "windowsdesktop-runtime-8.0.*-win-x64.exe"; Args = "/install /quiet /norestart"; AllowPattern = $true }
    )

    # --- Copiar e executar cada instalador ---
    foreach ($it in $installers) {
        $src = Resolve-SandboxInstallerSource -FileName $it.File -SearchRoots @($offlineDir, $toolsDir) -AllowPattern:([bool]$it.AllowPattern)

        if (-not $src) {
            Write-LogHost ('         [SKIP] {0} — instalador não encontrado: {1}' -f $it.Name, $it.File)
            continue
        }

        $realName = Split-Path -Leaf $src

        $dst = Join-Path $vmInstallDir $realName
        try {
            Write-LogHost ('         [COPY] {0} -> {1}' -f $it.Name, $dst)
            Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $src -DestinationPath $dst
        } catch {
            Write-LogWarning ('         Falha a copiar ''{0}'' para VM: {1}' -f $realName, $_.Exception.Message)
            continue
        }

        try {
            Write-LogHost ('         [RUN]  {0}' -f $it.Name)
            # *Executa instalador silenciosamente dentro da VM*
            $res = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($PathExe, $InstallerArgs)
                if (-not (Test-Path -LiteralPath $PathExe)) { return @{ ok = $false; code = -1; msg = "Instalador não encontrado no guest." } }
                $p = Start-Process -FilePath $PathExe -ArgumentList $InstallerArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                if (-not $p) { return @{ ok = $false; code = -2; msg = "Falha ao iniciar instalador." } }
                return @{ ok = $true; code = [int]$p.ExitCode; msg = "ok" }
            } -ArgumentList $dst, $it.Args -ErrorAction Stop

            $code = if ($res -and $res.code -ne $null) { [int]$res.code } else { 0 }
            # *ExitCode 0 = OK; 3010 = reboot necessário (aceitável)*
            if ($code -eq 0 -or $code -eq 3010) {
                Write-LogHost ('               OK (ExitCode={0})' -f $code)
            } else {
                Write-LogWarning ('               Instalador terminou com ExitCode={0} (pode requerer atenção).' -f $code)
            }
        } catch {
            Write-LogWarning ('         Erro ao executar ''{0}'' na VM: {1}' -f $it.Name, $_.Exception.Message)
        }
    }

    # --- Verificação rápida do dotnet ---
    try {
        $dotnetInfo = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            $p = Get-Command dotnet -ErrorAction SilentlyContinue
            if (-not $p) { return "dotnet: não encontrado" }
            try {
                $out = & dotnet --info 2>&1 | Select-Object -First 12
                return ($out -join [Environment]::NewLine)
            } catch { return "dotnet: erro ao executar --info" }
        } -ErrorAction SilentlyContinue
        if ($dotnetInfo) {
            Write-LogHost '       dotnet (resumo):'
            ($dotnetInfo -split '\r?\n') | ForEach-Object { Write-LogHost ('         ' + $_) }
        }
    } catch { }
}
