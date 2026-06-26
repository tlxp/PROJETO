# --- Módulo: HostSetup.ps1 ---
# --- Configuração de diretórios, rede e pré-requisitos do host ---

# --- Criação de diretório se não existir ---
function Ensure-DirectoryExists {
    param(
        [string] $Path
    )
    if (Test-Path $Path) { return }
    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Criaria diret-rio: $Path"
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# --- Alias para Ensure-DirectoryExists ---
function Ensure-Directory {
    param(
        [string] $Path
    )
    Ensure-DirectoryExists -Path $Path
}

# --- Verificação de pré-requisitos do sandbox ---
function Test-SandboxPrerequisites {
    [CmdletBinding()]
    param()

    $hv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
    if ($hv.State -ne "Enabled") {
        throw "Hyper-V n-o est- ativo. Ative Microsoft-Hyper-V e reinicie."
    }
}

# --- Criação de VMSwitch Internal se não existir ---
function Ensure-VMSwitchExists {
    param(
        [string] $SwitchName
    )
    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $existing) {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Criaria VMSwitch '$SwitchName' (Internal)."
        } else {
            New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        }
    }
}

# --- Alias para Ensure-VMSwitchExists ---
function Ensure-VMSwitch {
    param(
        [string] $Name
    )
    Ensure-VMSwitchExists -SwitchName $Name
}

# --- Validação de isolamento de rede da VM ---
function Assert-SandboxVmNetworkIsolation {
    <#
    .SYNOPSIS
        Valida que a VM só tem adaptadores em switches Internal e no switch esperado.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][string] $ExpectedSwitchName
    )

    $expectedSw = Get-VMSwitch -Name $ExpectedSwitchName -ErrorAction SilentlyContinue
    if (-not $expectedSw) {
        throw "Switch esperado '$ExpectedSwitchName' não encontrado no host."
    }
    if ($expectedSw.SwitchType -ne 'Internal') {
        throw "Switch '$ExpectedSwitchName' não é Internal (tipo: $($expectedSw.SwitchType))."
    }

    $adapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue)
    if ($adapters.Count -eq 0) {
        throw "VM '$VMName' não tem adaptadores de rede — isolamento não verificável."
    }

    # Cada adaptador deve estar no switch Internal esperado
    foreach ($adapter in $adapters) {
        $swName = $adapter.SwitchName
        if ([string]::IsNullOrWhiteSpace($swName)) {
            throw "Adaptador '$($adapter.Name)' da VM '$VMName' sem switch associado."
        }
        $sw = Get-VMSwitch -Name $swName -ErrorAction SilentlyContinue
        if (-not $sw) {
            throw "Adaptador '$($adapter.Name)' ligado a switch inexistente '$swName'."
        }
        if ($sw.SwitchType -ne 'Internal') {
            throw "Isolamento violado: adaptador '$($adapter.Name)' em switch '$swName' (tipo $($sw.SwitchType), esperado Internal)."
        }
        if ($swName -ne $ExpectedSwitchName) {
            throw "Adaptador '$($adapter.Name)' em switch '$swName' — esperado apenas '$ExpectedSwitchName'."
        }
    }

    Write-LogHost "Preflight rede OK: VM '$VMName' isolada no switch Internal '$ExpectedSwitchName' ($($adapters.Count) adaptador(es))."
}

# --- Obtenção do adaptador de rede do switch sandbox ---
function Get-SandboxNetAdapter {
    param(
        [string] $SwitchName
    )
    $adapter = $null
    try {
        $expectedName = "vEthernet ($SwitchName)"
        $adapter = Get-NetAdapter -Name $expectedName -ErrorAction SilentlyContinue
    } catch { $adapter = $null }

    # Fallback: procurar por nome parcial
    if (-not $adapter) {
        $adapter = Get-NetAdapter | Where-Object { $_.Name -eq "vEthernet ($SwitchName)" -or $_.Name -like "*$SwitchName*" } | Select-Object -First 1
    }
    return $adapter
}

# --- Atribuição de IP ao adaptador do switch no host ---
function Set-SandboxHostIpIfNeeded {
    param(
        [string] $SwitchName,
        [string] $IpAddress = "192.168.100.1",
        [int]    $PrefixLength = 24
    )
    $adapter = Get-SandboxNetAdapter -SwitchName $SwitchName
    if (-not $adapter) {
        Write-LogHost "Adaptador do switch '$SwitchName' n-o encontrado (ignorado)."
        return
    }

    $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not ($existing | Where-Object { $_.IPAddress -eq $IpAddress })) {
        if ($script:DryRun) {
            Write-LogHost "[DRY-RUN] Atribuiria IP ${IpAddress}/${PrefixLength} ao adaptador '$($adapter.Name)'."
        } else {
            try {
                New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IpAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
                Write-LogHost "IP ${IpAddress}/${PrefixLength} atribu-do ao adaptador do switch."
            } catch {
                Write-LogWarning "N-o foi poss-vel atribuir IP ${IpAddress}/${PrefixLength}: $($_.Exception.Message)"
            }
        }
    } else {
        Write-LogHost "Adaptador j- tem o IP ${IpAddress}/${PrefixLength} configurado."
    }

    Ensure-SandboxHostFirewall -SwitchName $SwitchName -RemoteSubnet "${IpAddress}/$PrefixLength"
}

# --- Regra de firewall para bloquear tráfego inbound da sandbox ---
function Ensure-SandboxHostFirewall {
    <#
    .SYNOPSIS
        Bloqueia tráfego inbound do host vindos da sub-rede da VM sandbox.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $SwitchName,
        [string] $RemoteSubnet = "192.168.100.0/24"
    )

    $ruleName = "PROJETOVM Block inbound from sandbox ($SwitchName)"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-LogHost "Firewall: regra '$ruleName' já existe."
        return
    }

    if ($script:DryRun) {
        Write-LogHost "[DRY-RUN] Criaria regra firewall inbound Block de $RemoteSubnet."
        return
    }

    try {
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Group "PROJETOVM Sandbox" `
            -Direction Inbound `
            -Action Block `
            -RemoteAddress $RemoteSubnet `
            -Profile Any `
            -Enabled True `
            -ErrorAction Stop | Out-Null
        Write-LogHost "Firewall: inbound de $RemoteSubnet bloqueado no host."
    } catch {
        Write-LogWarning "Não foi possível criar regra firewall: $($_.Exception.Message)"
    }
}
