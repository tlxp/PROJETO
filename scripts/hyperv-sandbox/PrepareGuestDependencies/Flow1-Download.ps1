# --- Módulo: Flow1-Download.ps1 ---
# --- Restore VM, arranque e download de dependências ---
# Downloads de dependências são feitos APENAS no host (Flow2); nunca via internet na VM.
# Carregado via dot-sourcing dentro do try/finally do script principal (mesmo scope).

# --- Catálogo de URLs de dependências offline ---
$urls = @(
    @{ family = "vcpp";     name = "VC_redist.x64.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x64.exe" },
    @{ family = "vcpp";     name = "VC_redist.x86.exe"; url = "https://aka.ms/vs/17/release/vc_redist.x86.exe" },
    @{ family = "webview2"; name = "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703" },
    @{ family = "dotnet";   name = "windowsdesktop-runtime-8.0.25-win-x64.exe"; url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.25/windowsdesktop-runtime-8.0.25-win-x64.exe" }
)

# --- Flag: operações na VM activas excepto em modo host-only ---
$DoVmOps = (-not $HostOnly)

# --- Restaurar snapshot e garantir isolamento de rede ---
if ($DoVmOps) {
    Write-LogHost "[1/6] A parar VM e restaurar snapshot limpo..."
    Stop-SandboxVM -VMName $VMName
    Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName

    Write-LogHost "[2/6] A garantir isolamento (sem adaptador TemporaryInternet)..."
    Remove-InternetAdapterIfAny -VMName $VMName
    $expectedSwitch = $script:PROJETOVM_SwitchName
    if ([string]::IsNullOrWhiteSpace($expectedSwitch)) {
        throw "PROJETOVM_SwitchName não definido em _Config.ps1."
    }
    # Valida que a VM só está ligada ao switch interno esperado
    Assert-SandboxVmNetworkIsolation -VMName $VMName -ExpectedSwitchName $expectedSwitch

    Write-LogHost "[3/6] A arrancar VM e aguardar PowerShell Direct..."
    try {
        $psOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds -LogPath $null
        # Start-SandboxVM pode devolver a credencial que funcionou
        if ($psOk -is [pscredential]) { $cred = $psOk }
    } catch {
        Write-LogWarning "Falha ao arrancar VM (ignorado; vou continuar em modo host-only): $($_.Exception.Message)"
        $DoVmOps = $false
    }
} else {
    Write-LogHost "[1/6] Modo host-only (sem Stop/Restore/Start da VM)."
}

# --- Activar Guest Services e preparar pasta deps na VM ---
if ($DoVmOps) {
    Write-LogHost "[4/6] A ativar Guest Services (para copiar ficheiros)..."
    Enable-SandboxGuestService -VMName $VMName
    $null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120

    try {
        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($VmDepsDir)
            $ErrorActionPreference = "Stop"
            # Cria C:\analysis_work\deps na VM para receber os instaladores
            if (-not (Test-Path -LiteralPath $VmDepsDir)) {
                New-Item -ItemType Directory -Path $VmDepsDir -Force | Out-Null
            }
        } -ArgumentList $VmDepsDir -ErrorAction Stop | Out-Null
    } catch {
        Write-LogWarning "Falha ao criar pasta deps na VM (ignorado): $($_.Exception.Message)"
    }
} else {
    Write-LogHost "[4/6] Modo host-only (sem Guest Services)."
}

Write-LogHost "[5/6] Downloads: apenas no host (sem internet na VM)."
