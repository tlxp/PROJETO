# --- Script: PhaseB-Resolve.ps1 ---

# --- Resolução de instaladores no host ---
$resolved = @()
$missing = @()
foreach ($it in $installers) {
    # *Se faltar, tentar download automático (quando ativado) para a pasta offline.*
    if ($it.Url) {
        $null = Download-InstallerIfMissing -Url $it.Url -OutFileName $it.File -Label $it.Name
    }
    $shared = Ensure-SharedInstaller -FileName $it.File -AllowPattern:([bool]$it.AllowPattern) -CacheLeafs $it.Cache
    if ($shared) {
        $resolved += @{ Name=$it.Name; File=$shared.FileName; HostPath=$shared.HostPath; Args=$it.Args }
        Write-LogHost ("[OK]   {0} -> {1}" -f $it.Name, $shared.HostPath)
    } else {
        $missing += $it
        Write-LogWarning ("[MISS] {0} (esperado: {1})" -f $it.Name, $it.File)
    }
}

# --- Validação: abortar se faltarem instaladores ---
if ($missing.Count -gt 0) {
    Write-LogHost ""
    Write-LogWarning "Faltam instaladores no host. Coloque-os em:"
    Write-LogWarning ("  - {0}" -f $OfflineDir)
    if ($SourceDir) { Write-LogWarning ("  - {0}" -f $SourceDir) }
    Write-LogWarning "E reexecute este script."
    Write-LogHost ""
    exit 2
}
