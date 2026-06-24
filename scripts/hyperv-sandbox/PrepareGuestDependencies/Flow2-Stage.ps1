# --- Script: Flow2-Stage.ps1 ---
# --- Parte 2: cache no host, manifest, cópia para VM e snapshot ---
# *Carregado via dot-sourcing dentro do try/finally do script principal (mesmo scope).*

    Write-LogHost "[6/6] A preparar ferramentas offline no projeto..."

    # --- Manifest de integridade das dependências ---
    $manifest = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        tools_dir = $HostToolsDir
        deps = @()
    }

    # --- Download no host e registo no manifest ---
    foreach ($u in $urls) {
        $vmPath = Join-Path $VmDepsDir $u.name
        $hostPath = Join-Path $HostToolsDir $u.name

        # *Copy-VMFile só copia Host->Guest; o cache canónico fica no host (tools/)*
        if (-not (Test-Path -LiteralPath $hostPath) -or $ForceRedownload) {
            Write-LogHost "      A descarregar no host: $($u.name)"
            Download-FileRobust -Url $u.url -DestinationPath $hostPath -Retries 3
        }
        if (Test-Path -LiteralPath $hostPath) {
            $manifest.deps += [pscustomobject]@{
                family = $u.family
                name = $u.name
                url = $u.url
                integrity = (Get-FileIntegrityInfo -Path $hostPath)
            }
        }
    }

    # --- Staging opcional do WinUtil (sem execução) ---
    if ($StageWinutil) {
        Write-LogHost "      A preparar WinUtil (modo seguro: apenas staging, sem executar/debloat)..."
        # *Fonte oficial (atalho estável) para o script WinUtil*
        # *NOTA: não executamos automaticamente para garantir que nada é removido*
        $winUrl = "https://christitus.com/win"
        if ((-not (Test-Path -LiteralPath $HostWinutilPath)) -or $ForceRedownload) {
            Download-FileRobust -Url $winUrl -DestinationPath $HostWinutilPath -Retries 3
        }
        if (Test-Path -LiteralPath $HostWinutilPath) {
            $manifest.deps += [pscustomobject]@{
                family = "winutil"
                name = "winutil.ps1"
                url = $winUrl
                integrity = (Get-FileIntegrityInfo -Path $HostWinutilPath)
            }
        }

        if ($DoVmOps) {
            try {
                Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $HostWinutilPath -DestinationPath (Join-Path $VmDepsDir "winutil.ps1")
                Write-LogHost "      WinUtil staged em: $VmDepsDir\\winutil.ps1"
            } catch {
                Write-LogWarning "      Falha ao copiar winutil.ps1 para a VM (ignorado): $($_.Exception.Message)"
            }
        }
    }

    # --- Cópia dos instaladores do host para a VM ---
    if ($DoVmOps) {
        try {
            foreach ($u in $urls) {
                $hostPath = Join-Path $HostToolsDir $u.name
                if (-not (Test-Path -LiteralPath $hostPath)) { continue }
                try {
                    Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $hostPath -DestinationPath (Join-Path $VmDepsDir $u.name)
                } catch {
                    Write-LogWarning "      Falha ao copiar '$($u.name)' para a VM (ignorado): $($_.Exception.Message)"
                }
            }
        } catch { }
    }

    # --- Persistência do manifest JSON ---
    try {
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DepsManifestPath -Encoding UTF8
        Write-LogHost "      Manifest de integridade guardado: $DepsManifestPath"
    } catch { }

    # --- Parar VM e revalidar isolamento de rede ---
    Write-LogHost "A parar VM e revalidar isolamento..."
    if ($DoVmOps) {
        Stop-SandboxVM -VMName $VMName
        Remove-InternetAdapterIfAny -VMName $VMName
        $expectedSwitch = $script:PROJETOVM_SwitchName
        if (-not [string]::IsNullOrWhiteSpace($expectedSwitch)) {
            Assert-SandboxVmNetworkIsolation -VMName $VMName -ExpectedSwitchName $expectedSwitch
        }
    } else {
        Write-LogHost "      Modo host-only (sem cleanup de VM)."
    }

    # --- Actualização opcional do snapshot CleanState ---
    if ($UpdateCleanSnapshot) {
        Write-LogHost "      A atualizar snapshot '$SnapshotName' (VM desligada, isolamento restaurado)..."
        try {
            # *Remove snapshot anterior antes de criar um novo*
            $old = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
            if ($old) { Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
        } catch { }
        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName | Out-Null
        Write-LogHost "      Snapshot atualizado."
    }

    Write-LogHost ""
    Write-LogHost "Concluído. Dependências disponíveis em: $HostToolsDir"
    Write-LogHost "Agora podes usar: 04-Run-Sample.ps1 -InstallDependencies VCpp"
