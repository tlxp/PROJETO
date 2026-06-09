# Auxiliares do first-time setup (host).
# Carregado via dot-sourcing (mesmo scope).

# Auxiliar: limpar e abortar em caso de erro
function Abort-WithCleanup {
    param([string] $Reason)
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO FATAL] $Reason"
    Write-LogHost "=========================================================="
    Write-LogHost "A parar VM por seguranca..."
    try { Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 4
    Write-LogHost "Cleanup concluido. Verifique os erros acima antes de reexecutar."
    exit 1
}

function Resolve-SandboxInstallerSource {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [Parameter(Mandatory = $true)][string[]] $SearchRoots,
        [switch] $AllowPattern
    )

    foreach ($root in @($SearchRoots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        if ($AllowPattern -and ($FileName -match "[\*\?]")) {
            try {
                $hit = Get-ChildItem -LiteralPath $root -File -Filter $FileName -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
                if ($hit) { return $hit.FullName }
            } catch { }
            continue
        }

        $candidate = Join-Path $root $FileName
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}
