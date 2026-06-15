# Instalação do Sysmon dentro da VM (via PowerShell Direct; sem Guest Services).
# Carregado via dot-sourcing (mesmo scope).

function Install-SysmonInSandboxGuest {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [string] $SysmonExePath = "",
        [string] $SysmonConfigPath = "",
        [switch] $SkipIfAlreadyInstalled
    )

    if ($SkipIfAlreadyInstalled) {
        $already = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
            if (-not $svc) { $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue }
            if (-not $svc) { return $false }
            $logPresent = $false
            try { $logPresent = [bool](Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue) } catch { }
            return ($svc.Status -eq "Running" -and $logPresent)
        } -ErrorAction SilentlyContinue
        if ($already) {
            Write-LogHost "      Sysmon já operacional na VM; instalação ignorada."
            return
        }
    }

    $resolvedExe = Resolve-SysmonExePath -PreferredPath $SysmonExePath
    $resolvedCfg = Resolve-SysmonConfigPath -PreferredPath $SysmonConfigPath -SysmonExeResolved $resolvedExe

    $guestSysmonDir    = "C:\tools\sysmon"
    $guestSysmonExe    = Join-Path $guestSysmonDir "Sysmon64.exe"
    $guestSysmonConfig = Join-Path $guestSysmonDir "sysmon-config.xml"

    Write-LogHost "      A copiar Sysmon para a VM (PowerShell Direct)..."
    Copy-SandboxVMFile -VMName $VMName -Credential $Credential -SourcePath $resolvedExe -DestinationPath $guestSysmonExe
    Copy-SandboxVMFile -VMName $VMName -Credential $Credential -SourcePath $resolvedCfg -DestinationPath $guestSysmonConfig

    Write-LogHost "      A instalar Sysmon dentro da VM..."
    Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
        param($exePath, $configPath)
        if (-not (Test-Path -LiteralPath $exePath)) {
            throw "Sysmon não encontrado dentro da VM em: $exePath"
        }
        if (-not (Test-Path -LiteralPath $configPath)) {
            throw "Configuração Sysmon não encontrada dentro da VM em: $configPath"
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.Arguments = "-accepteula -i `"$configPath`""
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $null = $proc.WaitForExit(600000)

        $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
        if (-not $svc) { $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue }
        if (-not $svc) {
            throw "Sysmon terminou (ExitCode $($proc.ExitCode)) mas o serviço Sysmon64/Sysmon não existe."
        }

        if ($svc.Status -ne "Running") {
            try {
                Start-Service -Name $svc.Name -ErrorAction Stop
                Start-Sleep -Milliseconds 500
                $svc = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            } catch { }
        }

        $logPresent = $false
        try { $logPresent = [bool](Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue) } catch { }

        if ($svc.Status -ne "Running" -or -not $logPresent) {
            throw ("Sysmon não ficou operacional. svc_status={0} log_present={1}" -f $svc.Status, $logPresent)
        }

        Write-Output ("Serviço: {0} | Estado: {1} | Canal Sysmon: {2}" -f $svc.Name, $svc.Status, $logPresent)
    } -ArgumentList $guestSysmonExe, $guestSysmonConfig -ErrorAction Stop | ForEach-Object {
        if ($_) { Write-LogHost ("      [VM] $_") }
    }
}
