function Get-LogTimestamp {
    return Get-Date -Format "HH:mm:ss"
}

function Write-LogHost {
    param([string] $Message)
    $t = Get-LogTimestamp
    Write-Host "[$t] $Message"
}

function Write-LogWarning {
    param([string] $Message)
    $t = Get-LogTimestamp
    Write-Warning "[$t] $Message"
}

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
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
        } catch { }
    }
}

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
