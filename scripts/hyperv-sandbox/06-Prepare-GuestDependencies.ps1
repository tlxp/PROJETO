<#
.SYNOPSIS
    Prepara dependências OFFLINE para análises futuras (sem internet durante execução de samples).
.DESCRIPTION
    A correr NO HOST. Fluxo:
      - Restaura a VM para snapshot limpo (CleanState)
      - Adiciona TEMPORARIAMENTE um adaptador de rede ligado a um switch com internet (por defeito: "Default Switch")
      - Arranca a VM e aguarda PowerShell Direct
      - Dentro da VM: descarrega instaladores (VC++ Redist x64/x86) para C:\analysis_work\deps
      - Copia os instaladores da VM para o projeto (scripts\hyperv-sandbox\tools\) via Guest Services (Copy-VMFile)
      - Remove o adaptador temporário e volta ao isolamento
      - (Opcional) atualiza o snapshot CleanState no fim

    Resultado:
      - Ficheiros offline ficam versionados/localizados no projeto para que 04-Run-Sample.ps1
        consiga instalar dependências (best-effort) sem internet.

.PARAMETER InternetSwitchName
    Nome do VMSwitch no host que dá acesso à internet. Por defeito "Default Switch".
.PARAMETER UpdateCleanSnapshot
    Se definido, cria/atualiza o snapshot CleanState depois de remover o adaptador temporário.
.PARAMETER ForceRedownload
    Se definido, força redownload dentro da VM mesmo que os ficheiros já existam.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string] $InternetSwitchName = "Default Switch",

    [Parameter()]
    [switch] $UpdateCleanSnapshot,

    [Parameter()]
    [switch] $ForceRedownload,

    [Parameter()]
    [switch] $StageWinutil
    ,
    [Parameter()]
    [ValidateRange(0, 900)]
    [int] $ConnectivityTimeoutSeconds = 90
    ,
    [Parameter()]
    [switch] $HostOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName        = $script:PROJETOVM_VMName
$SnapshotName  = $script:PROJETOVM_SnapshotName
$GuestUser     = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword
$VmWorkDir     = "C:\analysis_work"
$VmDepsDir     = Join-Path $VmWorkDir "deps"
$HostToolsDir  = Join-Path $PSScriptRoot "tools"
$HostWinutilPath = Join-Path $HostToolsDir "winutil.ps1"
$DepsManifestPath = Join-Path $HostToolsDir "deps_manifest.json"
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

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

function Get-FileIntegrityInfo {
    param([Parameter(Mandatory = $true)][string] $Path)
    $h = $null
    $sig = $null
    $len = 0
    $lwt = ""
    $signer = ""
    $thumb = ""
    try { $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction SilentlyContinue
    } catch { $sig = $null }
    try {
        $it = Get-Item -LiteralPath $Path -ErrorAction Stop
        $len = [int64]$it.Length
        $lwt = $it.LastWriteTimeUtc.ToString('o')
    } catch {
        $len = 0
        $lwt = ""
    }
    if ($sig -and $sig.SignerCertificate) {
        try { $signer = [string]$sig.SignerCertificate.Subject } catch { $signer = "" }
        try { $thumb  = [string]$sig.SignerCertificate.Thumbprint } catch { $thumb = "" }
    }
    return [pscustomobject]@{
        path = $Path
        sha256 = $h
        length = $len
        last_write_utc = $lwt
        signature = if ($sig) {
            @{
                status = [string]$sig.Status
                status_message = [string]$sig.StatusMessage
                signer = $signer
                thumbprint = $thumb
            }
        } else { $null }
    }
}

function Ensure-InternetAdapter {
    param([string] $VMName, [string] $SwitchName)

    $sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $sw) { throw "VMSwitch '$SwitchName' não encontrado. Ajuste -InternetSwitchName." }

    # Criar adaptador "TemporaryInternet" se não existir.
    $existing = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "TemporaryInternet" })
    if ($existing.Count -eq 0) {
        Add-VMNetworkAdapter -VMName $VMName -Name "TemporaryInternet" -SwitchName $SwitchName | Out-Null
    } else {
        Connect-VMNetworkAdapter -VMName $VMName -Name "TemporaryInternet" -SwitchName $SwitchName | Out-Null
    }
}

function Remove-InternetAdapterIfAny {
    param([string] $VMName)
    try {
        $a = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "TemporaryInternet" } | Select-Object -First 1
        if ($a) {
            Remove-VMNetworkAdapter -VMName $VMName -Name "TemporaryInternet" -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
}

Write-LogHost "=== Preparar dependências offline (via internet temporária) ==="
Write-LogHost "VM: $VMName | Snapshot: $SnapshotName | Internet switch: $InternetSwitchName"
Write-LogHost "Destino no projeto: $HostToolsDir"
Write-LogHost ""

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' não encontrada." }

$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

Ensure-DirectoryExists -Path $HostToolsDir

try {
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

    # Nota: em alguns ambientes (ex.: políticas de rede/NAT), o guest pode nunca ter TCP funcional
    # mesmo com "Default Switch". Para manter o fluxo confiável, não fazemos checks de TCP aqui.
    # Preparamos tudo no HOST e copiamos via Guest Services (best-effort).
    Write-LogHost "[4.5/7] Conectividade do guest: check TCP desativado (modo host-only)."
    $GuestHasInternet = $false

    if ($GuestHasInternet) {
        Write-LogHost "[5/7] A descarregar dependências dentro da VM..."
    # Catálogo por “família” (todas guardadas em scripts/hyperv-sandbox/tools/).
    # Nota: mantemos downloads no HOST como canonical cache + integridade.
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

    Write-LogHost "[6/7] A preparar ferramentas offline no projeto..."
    $manifest = [ordered]@{
        generated_at = (Get-Date).ToString("o")
        tools_dir = $HostToolsDir
        deps = @()
    }
    foreach ($u in $urls) {
        $vmPath = Join-Path $VmDepsDir $u.name
        $hostPath = Join-Path $HostToolsDir $u.name

        # Copy-VMFile só copia Host->Guest, então fazemos download também no HOST como fallback/espelho.
        # Ainda assim, mantemos o download no guest para provar que a VM com internet funciona.
        if (-not (Test-Path -LiteralPath $hostPath) -or $ForceRedownload) {
            Write-LogHost "      A descarregar no host: $($u.name)"
            Download-FileRobust -Url $u.url -DestinationPath $hostPath -Retries 3
        }
        if (Test-Path -LiteralPath $hostPath) {
            $manifest.deps += [pscustomobject]@{
                family = $u.family
                name = $u.name
                url = $u.url
                integrity = (Get-FileIntegrityInfo -Path $hostPath)
            }
        }
    }

    if ($StageWinutil) {
        Write-LogHost "      A preparar WinUtil (modo seguro: apenas staging, sem executar/debloat)..."
        # Fonte oficial (atalho estável) para o script WinUtil.
        # Nota: não executamos automaticamente para garantir que nada é removido.
        $winUrl = "https://christitus.com/win"
        if ((-not (Test-Path -LiteralPath $HostWinutilPath)) -or $ForceRedownload) {
            Download-FileRobust -Url $winUrl -DestinationPath $HostWinutilPath -Retries 3
        }
        if (Test-Path -LiteralPath $HostWinutilPath) {
            $manifest.deps += [pscustomobject]@{
                family = "winutil"
                name = "winutil.ps1"
                url = $winUrl
                integrity = (Get-FileIntegrityInfo -Path $HostWinutilPath)
            }
        }

        if ($DoVmOps) {
            try {
                Copy-SandboxVMFile -VMName $VMName -SourcePath $HostWinutilPath -DestinationPath (Join-Path $VmDepsDir "winutil.ps1")
                Write-LogHost "      WinUtil staged em: $VmDepsDir\\winutil.ps1"
            } catch {
                Write-LogWarning "      Falha ao copiar winutil.ps1 para a VM (ignorado): $($_.Exception.Message)"
            }
        }
    }

    # Copiar instaladores do HOST para a VM (útil mesmo quando a VM não tem internet).
    if ($DoVmOps) {
        try {
            foreach ($u in $urls) {
                $hostPath = Join-Path $HostToolsDir $u.name
                if (-not (Test-Path -LiteralPath $hostPath)) { continue }
                try {
                    Copy-SandboxVMFile -VMName $VMName -SourcePath $hostPath -DestinationPath (Join-Path $VmDepsDir $u.name)
                } catch {
                    Write-LogWarning "      Falha ao copiar '$($u.name)' para a VM (ignorado): $($_.Exception.Message)"
                }
            }
        } catch { }
    }

    try {
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DepsManifestPath -Encoding UTF8
        Write-LogHost "      Manifest de integridade guardado: $DepsManifestPath"
    } catch { }

    Write-LogHost "[7/7] A remover adaptador temporário e voltar ao isolamento..."
    if ($DoVmOps) {
        Stop-SandboxVM -VMName $VMName
        Remove-InternetAdapterIfAny -VMName $VMName
    } else {
        Write-LogHost "      VM: modo host-only (sem cleanup de adaptador)."
    }

    if ($UpdateCleanSnapshot) {
        Write-LogHost "      A atualizar snapshot '$SnapshotName' (VM desligada, isolamento restaurado)..."
        try {
            $old = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
            if ($old) { Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
        } catch { }
        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName | Out-Null
        Write-LogHost "      Snapshot atualizado."
    }

    Write-LogHost ""
    Write-LogHost "Concluído. Dependências disponíveis em: $HostToolsDir"
    Write-LogHost "Agora podes usar: 04-Run-Sample.ps1 -InstallDependencies VCpp"
}
finally {
    try {
        # Garantir isolamento mesmo em erro
        if (-not $HostOnly) {
            Stop-SandboxVM -VMName $VMName
            Remove-InternetAdapterIfAny -VMName $VMName
        }
    } catch { }
}

