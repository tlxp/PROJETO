# Corpo do try (parte 2): cache no host + manifest, cópia p/ VM, cleanup, snapshot.
# Carregado via dot-sourcing dentro do try/finally do script principal (mesmo scope).

    Write-LogHost "[6/7] A preparar ferramentas offline no projeto..."
    $manifest = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        tools_dir = $HostToolsDir
        deps = @()
    }
    foreach ($u in $urls) {
        $vmPath = Join-Path $VmDepsDir $u.name
        $hostPath = Join-Path $HostToolsDir $u.name

        # Copy-VMFile só copia Host->Guest, então fazemos download também no HOST como fallback/espelho.
        # Ainda assim, mantemos o download no guest para provar que a VM com internet funciona.
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

    if ($StageWinutil) {
        Write-LogHost "      A preparar WinUtil (modo seguro: apenas staging, sem executar/debloat)..."
        # Fonte oficial (atalho estável) para o script WinUtil.
        # NOTA: não executamos automaticamente para garantir que nada é removido.
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
                Copy-SandboxVMFile -VMName $VMName -SourcePath $HostWinutilPath -DestinationPath (Join-Path $VmDepsDir "winutil.ps1")
                Write-LogHost "      WinUtil staged em: $VmDepsDir\\winutil.ps1"
            } catch {
                Write-LogWarning "      Falha ao copiar winutil.ps1 para a VM (ignorado): $($_.Exception.Message)"
            }
        }
    }

    # Copiar instaladores do HOST para a VM (útil mesmo quando a VM não tem internet).
    if ($DoVmOps) {
        try {
            foreach ($u in $urls) {
                $hostPath = Join-Path $HostToolsDir $u.name
                if (-not (Test-Path -LiteralPath $hostPath)) { continue }
                try {
                    Copy-SandboxVMFile -VMName $VMName -SourcePath $hostPath -DestinationPath (Join-Path $VmDepsDir $u.name)
                } catch {
                    Write-LogWarning "      Falha ao copiar '$($u.name)' para a VM (ignorado): $($_.Exception.Message)"
                }
            }
        } catch { }
    }

    try {
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DepsManifestPath -Encoding UTF8
        Write-LogHost "      Manifest de integridade guardado: $DepsManifestPath"
    } catch { }

    Write-LogHost "[7/7] A remover adaptador temporário e voltar ao isolamento..."
    if ($DoVmOps) {
        Stop-SandboxVM -VMName $VMName
        Remove-InternetAdapterIfAny -VMName $VMName
    } else {
        Write-LogHost "      VM: modo host-only (sem cleanup de adaptador)."
    }

    if ($UpdateCleanSnapshot) {
        Write-LogHost "      A atualizar snapshot '$SnapshotName' (VM desligada, isolamento restaurado)..."
        try {
            $old = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
            if ($old) { Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
        } catch { }
        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName | Out-Null
        Write-LogHost "      Snapshot atualizado."
    }

    Write-LogHost ""
    Write-LogHost "Concluído. Dependências disponíveis em: $HostToolsDir"
    Write-LogHost "Agora podes usar: 04-Run-Sample.ps1 -InstallDependencies VCpp"
