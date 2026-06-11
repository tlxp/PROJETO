# Auxiliares do host: download robusto, integridade e cleanup de adaptadores órfãos.
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

function Remove-InternetAdapterIfAny {
    <#
    .SYNOPSIS
        Remove adaptador TemporaryInternet (legado) se existir — nunca é criado pelo fluxo actual.
    #>
    param([string] $VMName)
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm -and $vm.State -eq 'Running') {
            Stop-SandboxVM -VMName $VMName -ErrorAction SilentlyContinue
        }
        $adapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "TemporaryInternet" })
        foreach ($a in $adapters) {
            Write-LogHost "      A remover adaptador legado TemporaryInternet (switch: $($a.SwitchName))..."
            Remove-VMNetworkAdapter -VMName $VMName -Name $a.Name -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-LogWarning "Falha ao remover TemporaryInternet: $($_.Exception.Message)"
    }
}
