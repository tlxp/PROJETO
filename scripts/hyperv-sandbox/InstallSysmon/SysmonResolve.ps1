# Resolução de Sysmon (exe + config) e download robusto (host).
# Carregado via dot-sourcing (mesmo scope).

function Download-FileRobust {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $DestinationPath,
        [int] $Retries = 3
    )

    $lastErr = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            if (Test-Path -LiteralPath $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $DestinationPath)) {
                throw "Download terminou mas o ficheiro não existe: $DestinationPath"
            }
            return
        } catch {
            $lastErr = $_.Exception.Message
            if ($i -lt $Retries) { Start-Sleep -Seconds ([Math]::Min(10, 2 * $i)) }
        }
    }
    throw "Falha ao descarregar após ${Retries} tentativas. URL=$Url. Erro: $lastErr"
}

function Resolve-SysmonExePath {
    param([string] $PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return (Resolve-Path -LiteralPath $PreferredPath).Path
    }

    $candidates = @(
        "D:\Tools\Sysmon\Sysmon64.exe",
        "D:\Tools\Sysmon\Sysmon.exe",
        (Join-Path $script:PROJETOVM_BasePath "Tools\Sysmon\Sysmon64.exe"),
        (Join-Path $PSScriptRoot "tools\sysmon\Sysmon64.exe"),
        (Join-Path $PSScriptRoot "Sysmon64.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }

    # Download Sysmon.zip do Sysinternals e extrair
    $tmpDir = Join-Path $env:TEMP ("Sysmon_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $zipPath = Join-Path $tmpDir "Sysmon.zip"
    Write-Host "Sysmon não encontrado localmente. A descarregar do Sysinternals..."
    Download-FileRobust -Url "https://download.sysinternals.com/files/Sysmon.zip" -DestinationPath $zipPath -Retries 3
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmpDir -Force

    $exe = @(
        (Join-Path $tmpDir "Sysmon64.exe"),
        (Join-Path $tmpDir "Sysmon.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $exe) {
        throw "Sysmon.zip descarregado mas não foi possível localizar Sysmon64.exe no ZIP."
    }
    return $exe
}

function Resolve-SysmonConfigPath {
    param([string] $PreferredPath, [string] $SysmonExeResolved)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return (Resolve-Path -LiteralPath $PreferredPath).Path
    }

    $candidates = @(
        "D:\Tools\Sysmon\sysmon-config.xml",
        "D:\Tools\Sysmon\sysmonconfig.xml",
        (Join-Path $script:PROJETOVM_BasePath "Tools\Sysmon\sysmon-config.xml"),
        (Join-Path $PSScriptRoot "tools\sysmon\sysmon-config.xml"),
        (Join-Path $PSScriptRoot "sysmon-config.xml")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }

    # Tentar obter uma config bem conhecida; se falhar, gerar uma config mínima.
    $tmpDir = Split-Path -Parent $SysmonExeResolved
    $cfgPath = Join-Path $tmpDir "sysmon-config.xml"
    try {
        Write-Host "Config Sysmon não encontrada. A descarregar uma config default..."
        Download-FileRobust -Url "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -DestinationPath $cfgPath -Retries 3
        return $cfgPath
    } catch {
        Write-Warning "Não foi possível descarregar config default. A gerar config mínima: $($_.Exception.Message)"
        @"
<Sysmon schemaversion="4.90">
  <HashAlgorithms>*</HashAlgorithms>
  <EventFiltering>
  </EventFiltering>
</Sysmon>
"@ | Set-Content -LiteralPath $cfgPath -Encoding UTF8 -Force
        return $cfgPath
    }
}
