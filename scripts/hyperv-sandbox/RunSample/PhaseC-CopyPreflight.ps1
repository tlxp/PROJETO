# 6) Copiar amostra e scripts para a VM
Write-LogHost "[6/7] A copiar amostra para a VM..."
# Garantir que o diretório existe na VM
try {
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($Path)
        if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    } -ArgumentList $VMScriptsPath -ErrorAction SilentlyContinue
} catch { }

Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $SamplePath -DestinationPath $VMSamplePath

# Preflight: garantir que o ficheiro na VM existe e é o mesmo (SHA256) e que parece executável PE.
Write-LogHost "      A validar amostra dentro da VM (existência + SHA256 + header PE)..."
try {
    $vmCheck = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($PathLocal)
        $out = @{
            exists = $false
            sha256 = ""
            length = 0
            pe_ok = $false
            pe_reason = ""
            pe_machine = ""
        }
        if (-not (Test-Path -LiteralPath $PathLocal)) { return $out }
        $out.exists = $true
        try {
            $fi = Get-Item -LiteralPath $PathLocal -ErrorAction Stop
            $out.length = [int64]$fi.Length
        } catch { }
        try {
            $h = Get-FileHash -LiteralPath $PathLocal -Algorithm SHA256 -ErrorAction Stop
            $out.sha256 = $h.Hash
        } catch { }
        try {
            $fs = [System.IO.File]::Open($PathLocal, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $br = New-Object System.IO.BinaryReader($fs)
                $mz = $br.ReadUInt16()
                if ($mz -ne 0x5A4D) { $out.pe_ok = $false; $out.pe_reason = "Sem header MZ."; return $out }
                $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
                $peOff = $br.ReadUInt32()
                $fs.Seek([int64]$peOff, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sig = $br.ReadUInt32()
                if ($sig -ne 0x00004550) { $out.pe_ok = $false; $out.pe_reason = "Sem assinatura PE\\0\\0."; return $out }
                $machine = $br.ReadUInt16()
                $out.pe_ok = $true
                $out.pe_machine = switch ($machine) {
                    0x014c { "x86" }
                    0x8664 { "x64" }
                    0x01c4 { "ARM" }
                    0xAA64 { "ARM64" }
                    default { ("0x{0:X4}" -f $machine) }
                }
            } finally {
                try { $fs.Dispose() } catch { }
            }
        } catch {
            $out.pe_ok = $false
            $out.pe_reason = $_.Exception.Message
        }
        return $out
    } -ArgumentList $VMSamplePath -ErrorAction Stop

    if (-not $vmCheck.exists) { throw "Amostra não existe na VM em: $VMSamplePath" }
    if (-not $vmCheck.sha256 -or ($vmCheck.sha256.ToUpperInvariant() -ne $sampleSha256.ToUpperInvariant())) {
        throw "SHA256 não coincide dentro da VM. Esperado=$sampleSha256 Atual=$($vmCheck.sha256)"
    }
    if (-not $vmCheck.pe_ok) {
        throw "Amostra copiada mas não parece PE executável: $($vmCheck.pe_reason)"
    }
    Add-LogLine -Path $HostLogPath -Value "VM sample OK: len=$($vmCheck.length) sha256=$($vmCheck.sha256) machine=$($vmCheck.pe_machine)"
    Write-LogHost "      OK (machine: $($vmCheck.pe_machine))."
} catch {
    Add-LogLine -Path $HostLogPath -Value "VM sample preflight failed: $($_.Exception.Message)"
    throw
}

# Copiar scripts de análise para a VM
# NOTA: esta fase é dot-sourced a partir de .\RunSample\, por isso $PSScriptRoot aqui
# aponta para ...\RunSample. A pasta vm\ está na raiz hyperv-sandbox ($SandboxRoot).
$scriptDir = Join-Path $SandboxRoot "vm"
$runScript = Join-Path $scriptDir "Run-MalwareAnalysis.ps1"
if (-not (Test-Path -LiteralPath $runScript)) {
    throw "Run-MalwareAnalysis.ps1 não encontrado no host em: $runScript"
}
Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $runScript -DestinationPath "$VMScriptsPath\Run-MalwareAnalysis.ps1"

# Run-MalwareAnalysis.ps1 faz dot-source das suas funções da subpasta RunMalwareAnalysis\.
# Essas bibliotecas têm de existir na VM no mesmo diretório do script (mesmo $PSScriptRoot).
$analysisLibDir = Join-Path $scriptDir "RunMalwareAnalysis"
if (-not (Test-Path -LiteralPath $analysisLibDir)) {
    throw "Pasta de bibliotecas de análise não encontrada no host em: $analysisLibDir"
}
foreach ($lib in (Get-ChildItem -LiteralPath $analysisLibDir -Filter "*.ps1" -File)) {
    Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $lib.FullName -DestinationPath "$VMScriptsPath\RunMalwareAnalysis\$($lib.Name)"
}

foreach ($supportFile in @('noise_patterns.txt', 'benign_validation_hashes.txt')) {
    $supportPath = Join-Path $scriptDir $supportFile
    if (Test-Path -LiteralPath $supportPath) {
        Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $supportPath -DestinationPath "$VMScriptsPath\$supportFile"
    }
}

# Launcher destacado: corre Run-MalwareAnalysis.ps1 num processo separado dentro da VM
# para que a análise sobreviva ao fecho da sessão PowerShell Direct (VMBus).
$launchScript = Join-Path $scriptDir "Launch-AnalysisDetached.ps1"
if (-not (Test-Path -LiteralPath $launchScript)) {
    throw "Launch-AnalysisDetached.ps1 não encontrado no host em: $launchScript"
}
Copy-SandboxVMFile -VMName $VMName -Credential $cred -SourcePath $launchScript -DestinationPath "$VMScriptsPath\Launch-AnalysisDetached.ps1"

# Validar que o script principal chegou mesmo à VM antes de tentar executá-lo
# (evita o erro tardio "'.\Run-MalwareAnalysis.ps1' is not recognized" dentro da VM).
$runScriptInVm = "$VMScriptsPath\Run-MalwareAnalysis.ps1"
if (-not (Test-SandboxGuestPathExists -VMName $VMName -Credential $cred -GuestLiteralPath $runScriptInVm)) {
    throw "Run-MalwareAnalysis.ps1 não chegou à VM em: $runScriptInVm (cópia host->guest falhou)"
}
Write-LogHost "      Amostra e scripts copiados."
