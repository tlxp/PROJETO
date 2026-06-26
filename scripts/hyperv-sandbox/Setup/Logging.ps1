# --- Módulo: Logging.ps1 ---
# --- Logging do setup (dot-sourced pelo script principal) ---

function Log {
    param([string]$msg, [string]$level = "INFO")
    # delega escrita para Write-SandboxLog usando o $LogFile do script principal
    Write-SandboxLog -Message $msg -LogPath $LogFile -Level $level
}
