# --- Script: compile_python_locks.ps1 ---
# *Regenera requirements*.lock a partir dos ficheiros .txt editáveis (pip-tools).*
# *Uso: .\scripts\ci\compile_python_locks.ps1 — requer: pip install pip-tools*

$ErrorActionPreference = "Stop"
$backend = Join-Path $PSScriptRoot "..\..\backend" | Resolve-Path

$compileArgs = @(
    "--strip-extras",
    "--generate-hashes"
)

# --- Invocação do pip-compile para um par source/output ---
function Invoke-Compile {
    param(
        [string]$Source,
        [string]$Output
    )
    $srcPath = Join-Path $backend $Source
    $outPath = Join-Path $backend $Output
    Write-Host "pip-compile $Source -> $Output"
    # *Compila dependências com hashes para reprodutibilidade*
    python -m piptools compile $srcPath -o $outPath @compileArgs
}

# --- Compilação de todos os ficheiros lock do backend ---
Push-Location $backend
try {
    Invoke-Compile "requirements.txt" "requirements.lock"
    Invoke-Compile "requirements-dev.txt" "requirements-dev.lock"
    Invoke-Compile "requirements-gui.txt" "requirements-gui.lock"
    Invoke-Compile "requirements-ghidra.txt" "requirements-ghidra.lock"
    Write-Host "[OK] Locks regenerados em backend/"
}
finally {
    Pop-Location
}
