# --- Script: Helpers.ps1 ---
# Auxiliares do first-time setup (host).
# Carregado via dot-sourcing (mesmo scope).

# --- Limpar e abortar em caso de erro ---
function Abort-WithCleanup {
    param([string] $Reason)
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO FATAL] $Reason"
    Write-LogHost "=========================================================="
    Write-LogHost "A parar VM por seguranca..."
    # *Garante que a VM é desligada mesmo em falha fatal*
    try { Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 4
    Write-LogHost "Cleanup concluido. Verifique os erros acima antes de reexecutar."
    exit 1
}

# --- Resolver caminho de instalador offline ---
function Resolve-SandboxInstallerSource {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [Parameter(Mandatory = $true)][string[]] $SearchRoots,
        [switch] $AllowPattern
    )

    # *Percorre cada raiz de pesquisa até encontrar o ficheiro*
    foreach ($root in @($SearchRoots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        # *Suporta wildcards (ex.: windowsdesktop-runtime-8.0.*-win-x64.exe)*
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
