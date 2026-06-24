# --- Script: generate-production-secrets.ps1 ---
<#
.SYNOPSIS
    Gera segredos aleatórios para produção (API, vm-agent, password guest Hyper-V).
.DESCRIPTION
    Escreve ficheiros em secrets/ (gitignored) com variáveis prontas a carregar.
    Não altera o sistema — apenas gera e mostra instruções.
.EXAMPLE
    .\scripts\generate-production-secrets.ps1
    .\scripts\generate-production-secrets.ps1 -OutputDir D:\secure\ratanalyzer
#>
[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "secrets")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Geração de token seguro (Base64 URL-safe) ---
function New-SecureToken {
    param([int] $Bytes = 32)
    $buf = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    # *Base64 URL-safe sem padding — fácil de colar em variáveis de ambiente*
    [Convert]::ToBase64String($buf).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# --- Geração de password aleatória ---
function New-SecurePassword {
    param([int] $Length = 24)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*'
    $buf = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    # *Mapeia bytes aleatórios para caracteres do alfabeto definido*
    -join (0..($Length - 1) | ForEach-Object { $chars[$buf[$_] % $chars.Length] })
}

# --- Geração dos segredos e escrita em ficheiros ---
$apiToken = New-SecureToken
$vmToken = New-SecureToken
$guestPassword = New-SecurePassword

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$backendEnv = @"
# Gerado em $(Get-Date -Format o) — NÃO versionar
RATANALYZER_ENV=production
RATANALYZER_REQUIRE_API_TOKEN=1
RATANALYZER_API_TOKEN=$apiToken
VM_AGENT_TOKEN=$vmToken
"@

$frontendEnv = @"
# Gerado em $(Get-Date -Format o) — NÃO versionar
VITE_API_URL=http://127.0.0.1:8000
VITE_API_TOKEN=$apiToken
"@

$sandboxEnv = @"
# Gerado em $(Get-Date -Format o) — NÃO versionar
# PowerShell (sessão actual):
#   `$env:PROJETOVM_GuestPassword = '$guestPassword'
#   `$env:VM_AGENT_TOKEN = '$vmToken'
PROJETOVM_GuestPassword=$guestPassword
VM_AGENT_TOKEN=$vmToken
"@

$backendPath = Join-Path $OutputDir "backend.env"
$frontendPath = Join-Path $OutputDir "frontend.env"
$sandboxPath = Join-Path $OutputDir "sandbox.env"
$readmePath = Join-Path $OutputDir "README.txt"

$backendEnv | Set-Content -LiteralPath $backendPath -Encoding UTF8
$frontendEnv | Set-Content -LiteralPath $frontendPath -Encoding UTF8
$sandboxEnv | Set-Content -LiteralPath $sandboxPath -Encoding UTF8

$readme = @"
RAT Analyzer - segredos gerados
===============================

Ficheiros (gitignored):
  $backendPath
  $frontendPath
  $sandboxPath

Backend (uvicorn):
  Copie backend.env para backend/.env ou carregue no ambiente do serviço.
  Nunca use PROJETOVM_ALLOW_INSECURE_DEFAULTS nem VM_AGENT_ALLOW_INSECURE em produção.

Frontend (Vite):
  Copie frontend.env para frontend/.env antes de npm run build.

Sandbox Hyper-V (host + VM guest):
  Defina PROJETOVM_GuestPassword e VM_AGENT_TOKEN (ver sandbox.env).
  Na VM guest, configure VM_AGENT_TOKEN com o mesmo valor antes de arrancar VmAgent.exe.

WPF desktop:
  Defina RATANALYZER_API_TOKEN=$apiToken no ambiente do utilizador ou sistema
  (o WPF propaga-o ao backend e frontend ao arrancar).

Apague estes ficheiros se já não forem necessários.
"@
$readme | Set-Content -LiteralPath $readmePath -Encoding UTF8

Write-Host "Segredos gerados em: $OutputDir" -ForegroundColor Green
Write-Host '  backend.env   - RATANALYZER_API_TOKEN + VM_AGENT_TOKEN'
Write-Host '  frontend.env  - VITE_API_TOKEN (mesmo valor da API)'
Write-Host '  sandbox.env   - PROJETOVM_GuestPassword + VM_AGENT_TOKEN'
Write-Host ''
Write-Host ('Leia ' + $readmePath + ' para instruções de deploy.') -ForegroundColor Cyan
