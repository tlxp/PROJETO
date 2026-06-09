# Corpo do try (parte 1): restore, internet temporária, downloads no guest.
# Carregado via dot-sourcing dentro do try/finally do script principal (mesmo scope).

    $GuestHasInternet = $true
    $DoVmOps = (-not $HostOnly)

    if ($DoVmOps) {
        Write-LogHost "[1/7] A parar VM e restaurar snapshot limpo..."
        Stop-SandboxVM -VMName $VMName
        Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName

        Write-LogHost "[2/7] A adicionar adaptador temporário com internet..."
        Ensure-InternetAdapter -VMName $VMName -SwitchName $InternetSwitchName

        Write-LogHost "[3/7] A arrancar VM e aguardar PowerShell Direct..."
        try {
            $psOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds -LogPath $null
            if ($psOk -is [pscredential]) { $cred = $psOk }
        } catch {
            Write-LogWarning "Falha ao arrancar VM (ignorado; vou continuar em modo host-only): $($_.Exception.Message)"
            $DoVmOps = $false
        }
    } else {
        Write-LogHost "[1/7] VM: modo host-only (sem Stop/Restore/Start)."
        Write-LogHost "[2/7] VM: modo host-only (sem adaptador temporário)."
        Write-LogHost "[3/7] VM: modo host-only (sem PowerShell Direct)."
    }

    if ($DoVmOps) {
        Write-LogHost "[4/7] A ativar Guest Services (para copiar ficheiros)..."
        Enable-SandboxGuestService -VMName $VMName
        $null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120
    } else {
        Write-LogHost "[4/7] VM: modo host-only (sem Guest Services)."
    }

    # NOTA: em alguns ambientes (ex.: políticas de rede/NAT), o guest pode nunca ter TCP funcional
    # mesmo com "Default Switch". Para manter o fluxo confiável, não fazemos checks de TCP aqui.
    # Preparamos tudo no HOST e copiamos via Guest Services (best-effort).
    Write-LogHost "[4.5/7] Conectividade do guest: check TCP desativado (modo host-only)."
    $GuestHasInternet = $false

    if ($GuestHasInternet) {
        Write-LogHost "[5/7] A descarregar dependências dentro da VM..."
    # Catálogo por “família” (todas guardadas em scripts/hyperv-sandbox/tools/).
    # NOTA: mantemos downloads no HOST como cache canónica + integridade.
    $urls = @(
        @{ family = "vcpp";     name = "VC_redist.x64.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x64.exe" },
        @{ family = "vcpp";     name = "VC_redist.x86.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x86.exe" },
        @{ family = "webview2"; name = "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703" },
        # .NET Desktop Runtime (opcional, útil para apps desktop modernas). Mantemos x64; x86 pode ser adicionado se necessário.
        @{ family = "dotnet";   name = "windowsdesktop-runtime-8.0.25-win-x64.exe"; url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.25/windowsdesktop-runtime-8.0.25-win-x64.exe" }
    )

    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($VmDepsDir, $Urls, $Force)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"

        if (-not (Test-Path -LiteralPath $VmDepsDir)) { New-Item -ItemType Directory -Path $VmDepsDir -Force | Out-Null }

        # Forçar TLS moderno (PS 5.1 tende a falhar com TLS1.0/1.1).
        try {
            $sp = [System.Net.ServicePointManager]::SecurityProtocol
            # Tls12 existe em .NET 4.5+; Tls13 pode não existir em builds antigas (try/catch).
            $sp = $sp -bor [System.Net.SecurityProtocolType]::Tls12
            try { $sp = $sp -bor ([System.Net.SecurityProtocolType]::Tls13) } catch { }
            [System.Net.ServicePointManager]::SecurityProtocol = $sp
        } catch { }

        function DL-WebClient {
            param([string] $Url, [string] $OutPath)
            $wc = New-Object System.Net.WebClient
            try {
                $wc.Headers["User-Agent"] = "Mozilla/5.0"
                $wc.DownloadFile($Url, $OutPath)
            } finally {
                try { $wc.Dispose() } catch { }
            }
        }

        function DL {
            param([string] $Url, [string] $OutPath, [switch] $Force)
            if ((-not $Force) -and (Test-Path -LiteralPath $OutPath)) { return "SKIP: $(Split-Path -Leaf $OutPath) (já existe)" }
            try { Remove-Item -LiteralPath $OutPath -Force -ErrorAction SilentlyContinue } catch { }

            $last = $null
            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -ErrorAction Stop
            } catch {
                $last = $_.Exception.Message
                try {
                    DL-WebClient -Url $Url -OutPath $OutPath
                } catch {
                    $last = ($last + " | fallback: " + $_.Exception.Message)
                }
            }

            if (-not (Test-Path -LiteralPath $OutPath)) { throw "Download falhou: $OutPath | $last" }
            $len = (Get-Item -LiteralPath $OutPath).Length
            if ($len -lt 100000) { throw "Download suspeito (muito pequeno): $(Split-Path -Leaf $OutPath) len=$len" }
            return "OK: $(Split-Path -Leaf $OutPath) (${len} bytes)"
        }

        foreach ($u in $Urls) {
            $out = Join-Path $VmDepsDir $u.name
            $msg = DL -Url $u.url -OutPath $out -Force:([bool]$Force)
            Write-Host $msg
        }
    } -ArgumentList $VmDepsDir, $urls, $ForceRedownload.IsPresent -ErrorAction Stop | ForEach-Object {
        $s = ("" + $_).Trim()
        if ($s) { Write-LogHost "      [VM] $s" }
    }
    } else {
        Write-LogHost "[5/7] Downloads no guest ignorados (sem conectividade)."
        # Mesmo sem internet no guest, mantemos o catálogo para preparar o cache no host e copiar via Guest Services.
        $urls = @(
            @{ family = "vcpp";     name = "VC_redist.x64.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x64.exe" },
            @{ family = "vcpp";     name = "VC_redist.x86.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x86.exe" },
            @{ family = "webview2"; name = "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703" },
            @{ family = "dotnet";   name = "windowsdesktop-runtime-8.0.25-win-x64.exe"; url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.25/windowsdesktop-runtime-8.0.25-win-x64.exe" }
        )
        try {
            Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($VmDepsDir)
                $ErrorActionPreference = "Stop"
                if (-not (Test-Path -LiteralPath $VmDepsDir)) { New-Item -ItemType Directory -Path $VmDepsDir -Force | Out-Null }
            } -ArgumentList $VmDepsDir -ErrorAction Stop | Out-Null
        } catch { }
    }
