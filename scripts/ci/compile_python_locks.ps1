# --- Módulo: compile_python_locks.ps1 ---
# --- Regenera requirements*.lock via pip-tools (hashes reprodutíveis) ---

$ErrorActionPreference = "Stop"
$backend = Join-Path $PSScriptRoot "..\..\backend" | Resolve-Path
$postprocess = Join-Path $PSScriptRoot "postprocess_lock.py"

$compileArgs = @(
    "--strip-extras",
    "--generate-hashes",
    "--quiet"
)

function Invoke-Python {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3.11 @Args
    } else {
        & python @Args
    }
    if ($LASTEXITCODE -ne 0) { throw "Comando Python falhou: $Args" }
}

# --- Invocação do pip-compile para um par source/output ---
function Invoke-Compile {
    param(
        [string]$Source,
        [string]$Output
    )
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Write-Host "pip-compile $Source -> $Output"
        Invoke-Python -Args (@(
            "-m", "piptools", "compile",
            $Source, "-o", $tmp
        ) + $compileArgs)
        Invoke-Python -Args @($postprocess, $tmp, $Output)
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
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
