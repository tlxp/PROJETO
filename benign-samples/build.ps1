# --- Módulo: build.ps1 ---
# --- Compila todos os benign samples para benign-samples/dist/ ---
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $Dist | Out-Null

$Projects = @(
    "hello\BenignHello.csproj",
    "file-io\BenignFileIo.csproj",
    "http-ms\BenignHttpMs.csproj",
    "registry-read\BenignRegistryRead.csproj",
    "crypto-digest\BenignCryptoDigest.csproj",
    "env-dump\BenignEnvDump.csproj",
    "gui-msg\BenignGuiMsg.csproj"
)

foreach ($rel in $Projects) {
    $proj = Join-Path $Root $rel
    $name = [System.IO.Path]::GetFileNameWithoutExtension($proj)
    Write-Host "Publishing $name ..."
    dotnet publish $proj -c Release -o $Dist --nologo -v q
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: $proj" }
}

# --- BenignVmTest (sandbox): publish single-file se existir, senão Release ---
$VmTestProj = Join-Path $Root "..\benign-vm-test\BenignVmTest.csproj"
$VmPublish = Join-Path $Root "..\benign-vm-test\publish\BenignVmTest.exe"
if (-not (Test-Path $VmPublish)) {
    Write-Host "Publishing BenignVmTest ..."
    dotnet publish $VmTestProj -c Release -o (Join-Path $Root "..\benign-vm-test\publish") --nologo -v q
}
if (Test-Path $VmPublish) {
    Copy-Item -Force $VmPublish (Join-Path $Dist "BenignVmTest.exe")
}

Write-Host ""
Write-Host "Executáveis em: $Dist"
Get-ChildItem $Dist -Filter *.exe | ForEach-Object { Write-Host "  $($_.Name) ($([math]::Round($_.Length/1KB, 1)) KB)" }
