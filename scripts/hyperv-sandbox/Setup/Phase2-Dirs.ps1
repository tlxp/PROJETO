# Estrutura de diretórios
Write-Host "[2/8] Criando estrutura em $BasePath..."
foreach ($p in @($BasePath, $VMPath,
                 (Join-Path $BasePath "Reports"),
                 (Join-Path $BasePath "Samples"),
                 $LogsPath)) {
    Ensure-DirectoryExists -Path $p
}
