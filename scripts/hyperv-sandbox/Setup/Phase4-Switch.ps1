# --- Script: Phase4-Switch.ps1 ---
# --- Switch virtual isolado e firewall do host ---

Write-Host "[4/8] Switch virtual ($SwitchName)..."
Ensure-VMSwitch -Name $SwitchName

# --- Atribuição de IP ao adaptador do switch ---
$hostAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" } | Select-Object -First 1
if ($hostAdapter) {
    $hasIp = Get-NetIPAddress -InterfaceIndex $hostAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq "192.168.100.1" }
    if (-not $hasIp) {
        try {
            # *gateway do host na rede interna 192.168.100.0/24*
            New-NetIPAddress -InterfaceIndex $hostAdapter.ifIndex -IPAddress "192.168.100.1" -PrefixLength 24 -ErrorAction Stop | Out-Null
            Write-Host "      IP 192.168.100.1/24 atribuido."
        } catch { Write-Warning "      Não foi possível atribuir IP: $_" }
    } else {
        Write-Host "      Adaptador ja tem 192.168.100.1/24."
    }
} else {
    Write-Host "      Adaptador do switch não encontrado (ignorado)."
}

# --- Regras de firewall para o sandbox ---
Ensure-SandboxHostFirewall -SwitchName $SwitchName
