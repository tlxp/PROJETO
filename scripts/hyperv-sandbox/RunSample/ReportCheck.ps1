# Verificação de relatório + logging do host.
# Carregado via dot-sourcing (mesmo scope).

function Test-ReportLooksComplete {
    param([string] $Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $txt = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($txt)) { return $false }
        # O relatório está completo quando contém o cabeçalho e o rodapé gerados por Run-MalwareAnalysis.ps1
        if ($txt -notmatch "RELAT") { return $false }
        if ($txt -notmatch "FIM DO RELAT") { return $false }
        return $true
    } catch {
        return $false
    }
}

function Add-LogLine { param([string]$Path, [string]$Value) Add-Content -Path $Path -Value "[$(Get-Date -Format 'HH:mm:ss')] $Value" }
