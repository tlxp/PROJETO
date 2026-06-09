# Switch de rede isolado
Write-Host "[4/8] Switch virtual ($SwitchName)..."
Ensure-VMSwitch -Name $SwitchName

$hostAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" } | Select-Object -First 1
if ($hostAdapter) {
    $hasIp = Get-NetIPAddress -InterfaceIndex $hostAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq "192.168.100.1" }
    if (-not $hasIp) {
        try {
            New-NetIPAddress -InterfaceIndex $hostAdapter.ifIndex -IPAddress "192.168.100.1" -PrefixLength 24 -ErrorAction Stop | Out-Null
            Write-Host "      IP 192.168.100.1/24 atribuido."
        } catch { Write-Warning "      Nao foi possivel atribuir IP: $_" }
    } else {
        Write-Host "      Adaptador ja tem 192.168.100.1/24."
    }
} else {
    Write-Host "      Adaptador do switch nao encontrado (ignorado)."
}
