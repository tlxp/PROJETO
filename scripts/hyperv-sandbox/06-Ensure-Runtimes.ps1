<#
.SYNOPSIS
    Garante runtimes essenciais na VM (offline/sem internet).
.DESCRIPTION
    Script a correr NO HOST. Fluxo:
      1) Deteta/obtém instaladores no host (por ordem):
         - scripts/hyperv-sandbox/offline/runtimes/
         - -SourceDir (se fornecido)
         - C:\ProgramData\Package Cache (quando existir)
      2) Copia para uma pasta "partilhável" no host: D:\PROJETOVM\Shared\Installers
      3) Copia para a VM: C:\analysis_work\installers
      4) Instala silenciosamente dentro da VM (PowerShell Direct)

    Nota:
      - Por padrão, pode fazer download dos instaladores (host com internet) para a pasta offline do repo.
      - Se não houver internet, mantém o modo offline e indica quais faltam.
.PARAMETER SourceDir
    Pasta no host onde colocaste manualmente os instaladores (.exe).
.PARAMETER AutoDownload
    Se faltarem instaladores, tenta fazer download automático (links oficiais Microsoft) para `offline/runtimes/`.
.PARAMETER DownloadTimeoutSeconds
    Timeout por download (segundos).
.PARAMETER SkipDotNet48
    Não instalar .NET Framework 4.8.
.PARAMETER SkipDotNetDesktop
    Não instalar .NET Desktop Runtime 8.
.EXAMPLE
    .\06-Ensure-Runtimes.ps1 -SourceDir "D:\Installers"
#>
#Requires -RunAsAdministrator

param(
    [string] $SourceDir = "",
    [switch] $AutoDownload,
    [int] $DownloadTimeoutSeconds = 60,
    [switch] $SkipDotNet48,
    [switch] $SkipDotNetDesktop
)

$ErrorActionPreference = "Stop"

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName        = $script:PROJETOVM_VMName
$SnapshotName  = $script:PROJETOVM_SnapshotName
$BasePath      = $script:PROJETOVM_BasePath
$GuestUser     = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword

$SharedDir = Join-Path $BasePath "Shared\Installers"
Ensure-DirectoryExists -Path $SharedDir

$OfflineDir = Join-Path $PSScriptRoot "offline\runtimes"
Ensure-DirectoryExists -Path $OfflineDir

function Set-TlsForDownloads {
    try {
        # Garantir TLS 1.2+ em hosts mais antigos
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol `
            -bor [Net.SecurityProtocolType]::Tls12 `
            -bor [Net.SecurityProtocolType]::Tls13
    } catch { }
}

function Resolve-FinalUrl {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [int] $MaxRedirects = 12
    )

    Set-TlsForDownloads

    # Seguir redirecionamentos manualmente e parar quando não houver Location.
    # Nota: alguns links aka.ms devolvem HTML/cookies. Nesse caso, falhamos de forma explícita.
    $current = $Url
    for ($i = 0; $i -lt $MaxRedirects; $i++) {
        try {
            # HttpWebRequest tende a expor "Location" de forma mais consistente para alguns endpoints (aka.ms).
            # Usamos GET (não HEAD) porque alguns endpoints só redirecionam em GET.
            $req = [System.Net.HttpWebRequest]::Create($current)
            $req.AllowAutoRedirect = $false
            $req.Method = "GET"
            $req.UserAgent = "PROJETOVM/1.0"
            $req.Accept = "*/*"
            $req.Proxy = [System.Net.WebRequest]::DefaultWebProxy
            $req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
            $req.CookieContainer = New-Object System.Net.CookieContainer
            $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

            $resp = $req.GetResponse()
            $status = [int]$resp.StatusCode
            $loc = $resp.Headers["Location"]
            $ct = $null
            try { $ct = $resp.ContentType } catch { }

            if ($status -ge 300 -and $status -lt 400 -and $loc) {
                # Location pode ser relativo
                $nextUri = New-Object System.Uri((New-Object System.Uri($current)), $loc)
                $next = $nextUri.AbsoluteUri
                try { $resp.Close() } catch { }
                $current = $next
                continue
            }

            # Se chegámos aqui, não há redirect. Validar que parece um download direto quando esperamos .exe.
            try { $resp.Close() } catch { }
            return @{ Url = $current; Status = $status; ContentType = $ct }
        } catch {
            throw "Falha a resolver URL final para '$Url': $($_.Exception.Message)"
        } finally {
            try { if ($resp) { $resp.Close() } } catch { }
        }
    }

    throw "Demasiados redirecionamentos ao resolver URL: $Url"
}

function Resolve-DotnetDesktopRuntimeUrl {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("x86","x64")][string] $Arch
    )

    # Launcher oficial (pode redirecionar para download.visualstudio.microsoft.com)
    $launcher = "https://aka.ms/dotnet-core-applaunch?framework=Microsoft.WindowsDesktop.App&framework_version=8.0.0&arch=$Arch&rid=win-$Arch&os=win10&gui=true"
    $r = Resolve-FinalUrl -Url $launcher -MaxRedirects 15

    # Se acabar numa página HTML (ContentType text/html), é sinal de cookies/landing page.
    if ($r.ContentType -and $r.ContentType -match "text/html") {
        throw "URL do .NET Desktop Runtime ($Arch) resolveu para HTML (não é download direto). URL final: $($r.Url)"
    }
    if (-not ($r.Url -match "\.exe(\?|$)")) {
        throw "URL do .NET Desktop Runtime ($Arch) não parece um instalador .exe. URL final: $($r.Url)"
    }

    return $r.Url
}

function Download-InstallerIfMissing {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $OutFileName,
        [Parameter(Mandatory = $true)][string] $Label
    )

    # Se o nome tiver wildcard, inferir nome real a partir do URL final (inclui redirects).
    if ($OutFileName -match "[\*\?]") {
        try {
            $final = Resolve-FinalUrl -Url $Url -MaxRedirects 15
            $leaf = ([System.Uri]$final.Url).AbsolutePath
            $leaf = Split-Path -Leaf $leaf
            if (-not [string]::IsNullOrWhiteSpace($leaf)) { $OutFileName = $leaf }
        } catch { }
    }

    $dst = Join-Path $OfflineDir $OutFileName
    if (Test-Path -LiteralPath $dst) { return $dst }

    if (-not $AutoDownload) { return $null }

    Set-TlsForDownloads
    Write-LogHost ("[DL]  {0} -> {1}" -f $Label, $OutFileName)
    try {
        $tmp = $dst + ".download"
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $tmp -TimeoutSec $DownloadTimeoutSeconds -ErrorAction Stop | Out-Null
        Move-Item -LiteralPath $tmp -Destination $dst -Force
        return $dst
    } catch {
        Write-LogWarning ("Falha no download de '{0}': {1}" -f $Label, $_.Exception.Message)
        try { if (Test-Path -LiteralPath ($dst + ".download")) { Remove-Item -LiteralPath ($dst + ".download") -Force -ErrorAction SilentlyContinue } } catch { }
        return $null
    }
}

function Find-InstallerOnHost {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [switch] $AllowPattern,
        [string[]] $PackageCacheLeafNames = @()
    )

    $isPattern = $AllowPattern -and ($FileName -match "[\*\?]")

    # 1) Offline dir do repo (mais determinístico)
    if (-not $isPattern) {
        $p1 = Join-Path $OfflineDir $FileName
        if (Test-Path -LiteralPath $p1) { return $p1 }
    } else {
        try {
            $hit0 = Get-ChildItem -LiteralPath $OfflineDir -File -Filter $FileName -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($hit0) { return $hit0.FullName }
        } catch { }
    }

    # 2) SourceDir fornecido pelo utilizador
    if (-not [string]::IsNullOrWhiteSpace($SourceDir) -and (Test-Path -LiteralPath $SourceDir)) {
        if (-not $isPattern) {
            $p2 = Join-Path $SourceDir $FileName
            if (Test-Path -LiteralPath $p2) { return $p2 }
            # fallback: procurar por nome aproximado
            try {
                $hit = Get-ChildItem -LiteralPath $SourceDir -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ieq $FileName } |
                    Select-Object -First 1
                if ($hit) { return $hit.FullName }
            } catch { }
        } else {
            try {
                $hit = Get-ChildItem -LiteralPath $SourceDir -File -Recurse -Filter $FileName -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
                if ($hit) { return $hit.FullName }
            } catch { }
        }
    }

    # 3) Package Cache (quando o host já instalou o runtime no passado)
    $pkgRoot = "C:\ProgramData\Package Cache"
    if (Test-Path -LiteralPath $pkgRoot) {
        $leafs = @($FileName) + @($PackageCacheLeafNames)
        foreach ($leaf in $leafs) {
            try {
                if ($AllowPattern -and ($leaf -match "[\*\?]")) {
                    $hit2 = Get-ChildItem -LiteralPath $pkgRoot -File -Recurse -Filter $leaf -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending |
                        Select-Object -First 1
                } else {
                    $hit2 = Get-ChildItem -LiteralPath $pkgRoot -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ieq $leaf } |
                        Select-Object -First 1
                }
                if ($hit2) { return $hit2.FullName }
            } catch { }
        }
    }

    return $null
}

function Ensure-SharedInstaller {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [switch] $AllowPattern,
        [string[]] $CacheLeafs = @()
    )

    # Quando usamos padrões (wildcards), o ficheiro real pode ter versão no nome.
    if (-not ($AllowPattern -and ($FileName -match "[\*\?]"))) {
        $dst = Join-Path $SharedDir $FileName
        if (Test-Path -LiteralPath $dst) {
            return [pscustomobject]@{ HostPath = $dst; FileName = $FileName }
        }
    }

    $src = Find-InstallerOnHost -FileName $FileName -AllowPattern:$AllowPattern -PackageCacheLeafNames $CacheLeafs
    if (-not $src) { return $null }

    $realName = Split-Path -Leaf $src
    $dst = Join-Path $SharedDir $realName
    Copy-Item -LiteralPath $src -Destination $dst -Force
    return [pscustomobject]@{ HostPath = $dst; FileName = $realName }
}

$installers = @(
    @{
        Name="VC++ Redistributable (x86)"
        File="VC_redist.x86.exe"
        Args="/install /quiet /norestart"
        Cache=@("vc_redist.x86.exe")
        Url="https://aka.ms/vc14/vc_redist.x86.exe"
    },
    @{
        Name="VC++ Redistributable (x64)"
        File="VC_redist.x64.exe"
        Args="/install /quiet /norestart"
        Cache=@("vc_redist.x64.exe")
        Url="https://aka.ms/vc14/vc_redist.x64.exe"
    }
)

if (-not $SkipDotNet48) {
    $installers += @{
        Name=".NET Framework 4.8 (offline)"
        File="ndp48-x86-x64-allos-enu.exe"
        Args="/q /norestart"
        Cache=@("ndp48-x86-x64-allos-enu.exe")
        Url="https://go.microsoft.com/fwlink/?linkid=2088631"
    }
}

if (-not $SkipDotNetDesktop) {
    # Usar URL final resolvido + wildcard para aceitar versões reais (8.0.xx).
    $urlX86 = $null
    $urlX64 = $null
    try { $urlX86 = Resolve-DotnetDesktopRuntimeUrl -Arch "x86" } catch { Write-LogWarning $_.Exception.Message }
    try { $urlX64 = Resolve-DotnetDesktopRuntimeUrl -Arch "x64" } catch { Write-LogWarning $_.Exception.Message }

    $installers += @(
        @{
            Name=".NET Desktop Runtime 8 (x86)"
            File="windowsdesktop-runtime-8.0.*-win-x86.exe"
            AllowPattern=$true
            Args="/install /quiet /norestart"
            Cache=@()
            Url=$urlX86
        },
        @{
            Name=".NET Desktop Runtime 8 (x64)"
            File="windowsdesktop-runtime-8.0.*-win-x64.exe"
            AllowPattern=$true
            Args="/install /quiet /norestart"
            Cache=@()
            Url=$urlX64
        }
    )
}

Write-LogHost "=== Garantir runtimes essenciais (offline) ==="
Write-LogHost "VM: $VMName | Snapshot (referência): $SnapshotName"
Write-LogHost "Offline dir: $OfflineDir"
if ($SourceDir) { Write-LogHost "SourceDir: $SourceDir" }
Write-LogHost "Shared installers dir: $SharedDir"
Write-LogHost ("AutoDownload: {0} (timeout={1}s)" -f ([bool]$AutoDownload), $DownloadTimeoutSeconds)
Write-LogHost ""

$resolved = @()
$missing = @()
foreach ($it in $installers) {
    # Se faltar, tentar download automático (quando ativado) para a pasta offline
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

if ($missing.Count -gt 0) {
    Write-LogHost ""
    Write-LogWarning "Faltam instaladores no host. Coloque-os em:"
    Write-LogWarning ("  - {0}" -f $OfflineDir)
    if ($SourceDir) { Write-LogWarning ("  - {0}" -f $SourceDir) }
    Write-LogWarning "E reexecute este script."
    Write-LogHost ""
    exit 2
}

# Credenciais PowerShell Direct
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

Write-LogHost ""
Write-LogHost "A arrancar VM e a validar PowerShell Direct..."
$ps = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds 600
if ($ps -is [pscredential]) { $cred = $ps }
if (-not $ps) {
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO] PowerShell Direct não ficou disponível nesta fase."
    Write-LogHost "Isto normalmente significa OOBE/início de sessão ainda não concluído,"
    Write-LogHost "ou credenciais inválidas em `_Config.ps1` (GuestUser/GuestPassword)."
    Write-LogHost "Sugestão: corra primeiro `05-FirstTimeVmSetup.ps1` e confirme que a VM entra no Windows."
    Write-LogHost "=========================================================="
    Write-LogHost ""
    exit 3
}

$vmInstallDir = "C:\analysis_work\installers"
try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($Dir)
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    } -ArgumentList $vmInstallDir -ErrorAction Stop | Out-Null
} catch {
    Write-LogWarning "Não foi possível preparar '$vmInstallDir' na VM: $($_.Exception.Message)"
}

Write-LogHost ""
Write-LogHost "A copiar instaladores para a VM..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 2

foreach ($it in $resolved) {
    $dst = Join-Path $vmInstallDir $it.File
    Write-LogHost ("  [COPY] {0} -> {1}" -f $it.File, $dst)
    Copy-SandboxVMFile -VMName $VMName -SourcePath $it.HostPath -DestinationPath $dst
}

Write-LogHost ""
Write-LogHost "A instalar na VM (silencioso)..."
foreach ($it in $resolved) {
    $dst = Join-Path $vmInstallDir $it.File
    Write-LogHost ("  [RUN]  {0}" -f $it.Name)
    try {
        $res = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($PathExe, $Args)
            if (-not (Test-Path -LiteralPath $PathExe)) { return @{ ok = $false; code = -1; msg = "instalador ausente" } }
            $p = Start-Process -FilePath $PathExe -ArgumentList $Args -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
            if (-not $p) { return @{ ok = $false; code = -2; msg = "falha ao iniciar" } }
            return @{ ok = $true; code = [int]$p.ExitCode; msg = "ok" }
        } -ArgumentList $dst, $it.Args -ErrorAction Stop

        $code = if ($res -and $res.code -ne $null) { [int]$res.code } else { 0 }
        if ($code -eq 0 -or $code -eq 3010) {
            Write-LogHost ("        OK (ExitCode={0})" -f $code)
        } else {
            Write-LogWarning ("        ExitCode={0} (pode requerer atenção)" -f $code)
        }
    } catch {
        Write-LogWarning ("        Erro ao instalar: {0}" -f $_.Exception.Message)
    }
}

Write-LogHost ""
Write-LogHost "Sanity check: dotnet --info (se existir)..."
try {
    $dotnetInfo = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        $p = Get-Command dotnet -ErrorAction SilentlyContinue
        if (-not $p) { return "dotnet: não encontrado" }
        try { return (& dotnet --info 2>&1 | Select-Object -First 14) -join "`n" } catch { return "dotnet: erro ao executar --info" }
    } -ErrorAction SilentlyContinue
    if ($dotnetInfo) {
        ($dotnetInfo -split "`r?`n") | ForEach-Object { Write-LogHost ("  " + $_) }
    }
} catch { }

Write-LogHost ""
Write-LogHost "Concluído. (Se quiseres persistir isto no snapshot limpo, corre agora o 05-FirstTimeVmSetup.ps1 para criar novo CleanState.)"

