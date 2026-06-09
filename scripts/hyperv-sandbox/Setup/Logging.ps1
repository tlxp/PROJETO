# Logging do setup (escreve no $LogFile do script principal).
# Carregado via dot-sourcing (mesmo scope).

function Log {
    param([string]$msg, [string]$level = "INFO")
    Write-SandboxLog -Message $msg -LogPath $LogFile -Level $level
}
