# --- Script: Logging.ps1 ---

# --- Timestamp para mensagens de log ---
function Get-LogTimestamp {
    return Get-Date -Format "HH:mm:ss"
}

# --- Log simples no consola (host) ---
function Write-LogHost {
    param([string] $Message)
    # *Formatar mensagem com timestamp e escrever no host*
    $t = Get-LogTimestamp
    Write-Host "[$t] $Message"
}

# --- Log de aviso com timestamp ---
function Write-LogWarning {
    param([string] $Message)
    $t = Get-LogTimestamp
    Write-Warning "[$t] $Message"
}

# --- Log estruturado com nível e persistência opcional em ficheiro ---
function Write-SandboxLog {
    param(
        [string] $Message,
        [string] $LogPath,
        [ValidateSet("INFO","WARN","ERROR")]
        [string] $Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    # *Anexar linha ao ficheiro de log se o caminho foi fornecido*
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
        } catch { }
    }
}

# --- Escrita de log em formato JSON ---
function Write-SandboxJsonLog {
    param(
        [hashtable] $Data,
        [string] $JsonPath
    )
    if (-not $JsonPath) { return }
    try {
        $json = $Data | ConvertTo-Json -Depth 6
        $json | Set-Content -Path $JsonPath -Encoding UTF8
    } catch { }
}
