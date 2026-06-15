function Wait-VMHeartbeatOk {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [int] $TimeoutSeconds = 2400,
        [string] $LogPath,
        [int] $LogIntervalSeconds = 5
    )
    if ($script:DryRun) { return $true }
    $start = Get-Date
    $deadline = $start.AddSeconds($TimeoutSeconds)
    Write-SandboxLog -Message "A aguardar Heartbeat da VM '$VMName' (timeout ${TimeoutSeconds}s, intervalo ${LogIntervalSeconds}s)..." -LogPath $LogPath -Level "INFO"

    $lastPrimary = $null
    $lastSecondary = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $hb = Get-VMIntegrationService -VMName $VMName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Heartbeat*" -or $_.Id -like "*Heartbeat*" } | Select-Object -First 1

            if (-not $hb) {
                $elapsed = [int]((Get-Date) - $start).TotalSeconds
                Write-SandboxLog -Message "Heartbeat: serviço de integração não encontrado (ainda). elapsed=${elapsed}s" -LogPath $LogPath -Level "INFO"
            } else {
                $primary = $hb.PrimaryStatusDescription
                $secondary = $null
                try { $secondary = $hb.SecondaryStatusDescription } catch { }

                if ($primary -ne $lastPrimary -or $secondary -ne $lastSecondary) {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat status mudou: Primary='$primary' Secondary='$secondary' (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                    $lastPrimary = $primary
                    $lastSecondary = $secondary
                } else {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat: Primary='$primary' Secondary='$secondary' (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                }

                if ($primary -eq "OK") {
                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "Heartbeat da VM '$VMName' ficou OK após ${elapsed}s." -LogPath $LogPath -Level "INFO"
                    return $true
                }
            }
        } catch { }
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        Write-SandboxLog -Message "Heartbeat ainda não OK. Tempo restante aproximado: ${remaining}s." -LogPath $LogPath -Level "INFO"

        Start-Sleep -Seconds $LogIntervalSeconds
    }
    Write-SandboxLog -Message "Timeout - espera do Heartbeat da VM '$VMName' ap-s ${TimeoutSeconds}s." -LogPath $LogPath -Level "WARN"
    return $false
}

function New-SandboxCredentialCandidates {
    param(
        [Parameter(Mandatory = $true)][string] $UserName,
        [Parameter(Mandatory = $true)][string] $Password,
        [string] $ComputerName
    )
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force

    $userNames = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        $userNames.Add($UserName)
    }

    # Se não houver domínio explícito, tentar variações comuns para conta local.
    $hasQualifier = ($UserName -match "\\") -or ($UserName -match "@")
    if (-not $hasQualifier) {
        $userNames.Add(".\$UserName")
        if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
            $userNames.Add("$ComputerName\$UserName")
        }
    }

    # Remover duplicados preservando ordem
    $seen = @{}
    $final = @()
    foreach ($u in $userNames) {
        if (-not $seen.ContainsKey($u)) {
            $seen[$u] = $true
            $final += $u
        }
    }

    return @($final | ForEach-Object { [pscredential]::new($_, $secure) })
}

function Test-PowerShellDirectAuthError {
    param([string] $Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    $patterns = @(
        'user name or password',
        'password is incorrect',
        'account is currently locked',
        'referenced account is currently locked',
        'logon failure',
        'access is denied',
        'authentication failed',
        'nome de utilizador ou palavra-passe',
        'palavra-passe.*incorrect',
        'conta.*bloqueada',
        'account.*locked'
    )
    foreach ($p in $patterns) {
        if ($Message -match $p) { return $true }
    }
    return $false
}

function Wait-VMPowerShellDirectReady {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [pscredential] $Credential,
        [pscredential[]] $CredentialCandidates,
        # TimeoutSeconds:
        # - >0  : timeout normal
        # - <=0 : sem timeout (espera indefinidamente)
        [int] $TimeoutSeconds = 0,
        [string] $LogPath,
        [int] $LogIntervalSeconds = 10,
        # Após N ciclos seguidos só com erros de autenticação, parar (evita lockout infinito).
        [int] $MaxAuthFailureAttempts = 15
    )
    if ($script:DryRun) { return $true }

    $candidates = @()
    if ($CredentialCandidates -and $CredentialCandidates.Count -gt 0) {
        $candidates = @($CredentialCandidates)
    } elseif ($Credential) {
        $candidates = @($Credential)
    } else {
        throw "Wait-VMPowerShellDirectReady: forneça -Credential ou -CredentialCandidates."
    }

    $start = Get-Date
    $deadline = $null
    if ($TimeoutSeconds -gt 0) { $deadline = $start.AddSeconds($TimeoutSeconds) }
    $timeoutLabel = if ($TimeoutSeconds -gt 0) { "${TimeoutSeconds}s" } else { "sem timeout" }
    Write-SandboxLog -Message "A aguardar PowerShell Direct na VM '$VMName' (timeout: $timeoutLabel, intervalo ${LogIntervalSeconds}s)..." -LogPath $LogPath -Level "INFO"

    $lastErr = $null
    $authFailureStreak = 0
    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) { break }
        $loopHadAuthError = $false
        try {
            foreach ($cand in $candidates) {
                try {
                    # PowerShell Direct (Invoke-Command -VMName) não depende de rede/WinRM.
                    # Ele normalmente só começa a funcionar quando o Windows convidado já arrancou e aceita logon com as credenciais.
                    $null = Invoke-Command -VMName $VMName -Credential $cand -ScriptBlock { 1 } -ErrorAction Stop

                    $elapsed = [int]((Get-Date) - $start).TotalSeconds
                    Write-SandboxLog -Message "PowerShell Direct OK na VM '$VMName' após ${elapsed}s (user='$($cand.UserName)')." -LogPath $LogPath -Level "INFO"
                    return $cand
                } catch {
                    $msg = $($_.Exception.Message)
                    $lastErr = $msg
                    if (Test-PowerShellDirectAuthError $msg) {
                        $loopHadAuthError = $true
                        if ($msg -match 'locked') {
                            Write-SandboxLog -Message "Conta bloqueada na VM (user='$($cand.UserName)'): $msg. Parar tentativas — restaure snapshot CleanState ou aguarde o lockout expirar." -LogPath $LogPath -Level "ERROR"
                            return $null
                        }
                    }
                }
            }
        } catch {
            $msg = $($_.Exception.Message)
            if ($msg -ne $lastErr) {
                $elapsed = [int]((Get-Date) - $start).TotalSeconds
                Write-SandboxLog -Message "PowerShell Direct ainda indisponível: $msg (elapsed=${elapsed}s)" -LogPath $LogPath -Level "INFO"
                $lastErr = $msg
            }
            if (Test-PowerShellDirectAuthError $msg) { $loopHadAuthError = $true }
        }

        if ($loopHadAuthError) {
            $authFailureStreak++
            if ($authFailureStreak -ge $MaxAuthFailureAttempts) {
                $uList = ($candidates | ForEach-Object { $_.UserName }) -join ", "
                Write-SandboxLog -Message "PowerShell Direct: $MaxAuthFailureAttempts tentativas seguidas com erro de autenticação (users: $uList). Último erro: $lastErr. Verifique se a password coincide com a conta na VM (autounattend / primeira instalação)." -LogPath $LogPath -Level "ERROR"
                return $null
            }
        } else {
            $authFailureStreak = 0
        }

        $elapsed = [int]((Get-Date) - $start).TotalSeconds
        if ($deadline) {
            Write-SandboxLog -Message "PowerShell Direct ainda não OK. Tempo decorrido: ${elapsed}s (timeout ${TimeoutSeconds}s)." -LogPath $LogPath -Level "INFO"
        } else {
            $uList = ($candidates | ForEach-Object { $_.UserName }) -join ", "
            Write-SandboxLog -Message "PowerShell Direct ainda não OK (elapsed=${elapsed}s). Tentando users: $uList" -LogPath $LogPath -Level "INFO"
        }
        Start-Sleep -Seconds $LogIntervalSeconds
    }

    Write-SandboxLog -Message "Timeout - espera do PowerShell Direct na VM '$VMName' após ${TimeoutSeconds}s." -LogPath $LogPath -Level "WARN"
    return $null
}

function Get-SandboxGuestServiceName {
    param([string] $VMName)

    function _Normalize-Ascii {
        param([AllowNull()][string] $s)
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        try {
            $formD = $s.Normalize([Text.NormalizationForm]::FormD)
            $sb = New-Object System.Text.StringBuilder
            foreach ($ch in $formD.ToCharArray()) {
                $uc = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
                if ($uc -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                    [void]$sb.Append($ch)
                }
            }
            return $sb.ToString().ToLowerInvariant()
        } catch {
            return ($s.ToLowerInvariant())
        }
    }

    try {
        $services = Get-VMIntegrationService -VMName $VMName -ErrorAction Stop

        # 1) Preferir match estável por Id/Description quando possível (alguns hosts expõem Ids como GUID).
        $svc = $services | Where-Object {
            ($_.Id -is [string] -and (($_.Id -like "*Guest*Service*") -or ($_.Id -like "*Guest*Interface*"))) -or
            ($_.Description -is [string] -and (($_.Description -like "*Guest Service*") -or ($_.Description -like "*Guest Service Interface*")))
        } | Select-Object -First 1
        if ($svc) { return $svc.Name }

        # 2) Fallback robusto por nome/descrição, ignorando acentos/idioma
        $targets = @(
            "guest service interface",
            "guest services",
            "interface de serviço convidado",
            "serviço convidado",
            "serviços de convidado"
        )

        $svc = $services | ForEach-Object {
            $n = _Normalize-Ascii $_.Name
            $d = _Normalize-Ascii $_.Description
            $hit = $false
            foreach ($t in $targets) {
                if ($n -like "*$t*" -or $d -like "*$t*") { $hit = $true; break }
            }
            if ($hit) { $_ }
        } | Select-Object -First 1

        if ($svc) { return $svc.Name }

        # 3) Último recurso: qualquer serviço cujo Name/Id contenha "guest" (exclui Heartbeat/shutdown).
        $svc = $services | Where-Object {
            $n = _Normalize-Ascii $_.Name
            $id = _Normalize-Ascii ([string]$_.Id)
            ($n -like "*guest*" -or $id -like "*guest*") -and
            ($n -notlike "*heartbeat*") -and ($n -notlike "*shutdown*") -and ($n -notlike "*time*sync*")
        } | Select-Object -First 1
        if ($svc) { return $svc.Name }
    } catch { }
    return $null
}

function Enable-SandboxGuestService {
    param([string] $VMName)
    if ($script:DryRun) { return }
    if (-not $script:PROJETOVM_UseGuestServices) { return }
    $name = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $name) {
        Write-LogWarning "Guest Service (Integration Service) n-o encontrado/indispon-vel na VM '$VMName'."
        Write-LogWarning "Isto normalmente significa que o Windows na VM ainda n-o est- instalado/arrancado, ou que o servi-o de integra--o 'Guest Services' n-o est- dispon-vel."
        return
    }
    Enable-VMIntegrationService -VMName $VMName -Name $name -ErrorAction SilentlyContinue
}

function Disable-SandboxGuestService {
    param([string] $VMName)
    if ($script:DryRun) { return }
    $name = Get-SandboxGuestServiceName -VMName $VMName
    if (-not $name) { return }
    Disable-VMIntegrationService -VMName $VMName -Name $name -ErrorAction SilentlyContinue
}
