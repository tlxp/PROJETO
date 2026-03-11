<#
.SYNOPSIS
    Ajusta a VM para parecer um desktop real de utilizador (camuflagem anti-sandbox).
.DESCRIPTION
    A correr DENTRO da VM uma vez, antes de criar o snapshot limpo.
    Altera hostname, cria utilizador "realista", ajusta serviços Hyper-V
    e opcionalmente instala software comum via winget.
#>

param(
    [string] $NewComputerName = "DESKTOP-A47K9P",
    [string] $UserName = "joao",
    [string] $UserPassword = "P@ssword123",
    [switch] $InstallCommonSoftware
)

$ErrorActionPreference = "Stop"

Write-Host "=== Preparação de ambiente realista na VM ==="

# 1) Alterar hostname (requer reboot posterior)
if ($env:COMPUTERNAME -ne $NewComputerName) {
    Write-Host "A alterar nome da máquina para $NewComputerName (requer reboot)..."
    Rename-Computer -NewName $NewComputerName -Force
}

# 2) Criar utilizador "realista" e adicioná-lo a Administrators
try {
    if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
        Write-Host "A criar utilizador local: $UserName"
        $secure = ConvertTo-SecureString $UserPassword -AsPlainText -Force
        New-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires:$true -AccountNeverExpires:$true | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Warning "Falha ao criar utilizador realista: $_"
}

# 3) Desativar serviços de integração Hyper-V visíveis (se não forem necessários)
$services = @("vmictimesync","vmicvss","vmicshutdown")
foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "A parar e desativar serviço $svc..."
        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Falha ao ajustar serviço $svc: $_"
        }
    }
}

# 4) Ajustar algumas strings de BIOS para parecer hardware genérico
try {
    $biosKey = "HKLM:\HARDWARE\DESCRIPTION\System\BIOS"
    if (Test-Path $biosKey) {
        Set-ItemProperty -Path $biosKey -Name "SystemManufacturer" -Value "Dell Inc." -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $biosKey -Name "SystemProductName" -Value "XPS 15 9500" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Warning "Falha ao ajustar chaves de BIOS: $_"
}

# 5) Instalar software comum (opcional, via winget) — utilizador do dia a dia
if ($InstallCommonSoftware) {
    Write-Host "A instalar software comum via winget (pode demorar)..."
    $packages = @(
        "Google.Chrome",
        "7zip.7zip",
        "Microsoft.VisualStudioCode",
        "Notepad++.Notepad++",
        "VideoLAN.VLC",
        "Microsoft.PowerToys"
    )
    foreach ($pkg in $packages) {
        try {
            Write-Host "  A instalar: $pkg"
            winget install --id $pkg -e --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Warning "Falha ao instalar $pkg: $_"
        }
    }
}

Write-Host "Preparação concluída. Recomenda-se reiniciar a VM e atualizar o snapshot limpo."

