# --- Script: Phase2-Dirs.ps1 ---
# --- Criação da estrutura de diretórios do sandbox ---

Write-Host "[2/8] Criando estrutura em $BasePath..."
foreach ($p in @($BasePath, $VMPath,
                 (Join-Path $BasePath "Reports"),
                 (Join-Path $BasePath "Samples"),
                 $LogsPath)) {
    # *garante que cada pasta base existe antes das fases seguintes*
    Ensure-DirectoryExists -Path $p
}
