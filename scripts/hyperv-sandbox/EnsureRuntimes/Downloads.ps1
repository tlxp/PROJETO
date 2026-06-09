# Resolução de URLs e download de instaladores (host).
# Carregado via dot-sourcing (mesmo scope).

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
    # NOTA: alguns links aka.ms devolvem HTML/cookies. Nesse caso, falhamos de forma explícita.
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
