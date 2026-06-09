# Execução da análise dentro da VM via Invoke-Command.
# Carregado via dot-sourcing (mesmo scope).

function Invoke-RunAnalysisInVm {
    param(
        [string] $VM,
        [pscredential] $Cred,
        [string] $VmSamplePath,
        [int] $TimeoutSec,
        [string] $VmScriptDir,
        [string] $SampleSha256
    )

    $vmOutput = Invoke-Command -VMName $VM -Credential $Cred -ScriptBlock {
        param($SamplePathLocal, $TimeoutSec, $ScriptPath, $SampleSha256)
        Set-Location $ScriptPath
        & ".\Run-MalwareAnalysis.ps1" -SamplePath $SamplePathLocal -TimeoutSeconds $TimeoutSec -SampleHash $SampleSha256 -ErrorAction Stop
    } -ArgumentList $VmSamplePath, $TimeoutSec, $VmScriptDir, $SampleSha256 -ErrorAction Stop

    foreach ($l in @($vmOutput)) {
        if ($null -eq $l) { continue }
        $s = ($l | Out-String).TrimEnd()
        if (-not $s -or $s -eq "True") { continue }
        Write-LogHost ("      [VM] {0}" -f $s)
    }
}
