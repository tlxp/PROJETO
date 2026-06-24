# --- Script: PhaseA-Plan.ps1 ---

# --- Definição da lista de instaladores ---
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

# --- .NET Framework 4.8 (opcional) ---
if (-not $SkipDotNet48) {
    $installers += @{
        Name=".NET Framework 4.8 (offline)"
        File="ndp48-x86-x64-allos-enu.exe"
        Args="/q /norestart"
        Cache=@("ndp48-x86-x64-allos-enu.exe")
        Url="https://go.microsoft.com/fwlink/?linkid=2088631"
    }
}

# --- .NET Desktop Runtime 8 (opcional) ---
if (-not $SkipDotNetDesktop) {
    # *Resolver URLs finais e usar wildcard para aceitar versões reais (8.0.xx).*
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

# --- Registo de contexto da execução ---
Write-LogHost "=== Garantir runtimes essenciais (offline) ==="
Write-LogHost "VM: $VMName | Snapshot (referência): $SnapshotName"
Write-LogHost "Offline dir: $OfflineDir"
if ($SourceDir) { Write-LogHost "SourceDir: $SourceDir" }
Write-LogHost "Shared installers dir: $SharedDir"
Write-LogHost ("AutoDownload: {0} (timeout={1}s)" -f ([bool]$AutoDownload), $DownloadTimeoutSeconds)
Write-LogHost ""
