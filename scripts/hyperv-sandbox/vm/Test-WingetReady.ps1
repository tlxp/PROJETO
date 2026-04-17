param([int]$MaxWaitSeconds = 120)

$start = Get-Date
$deadline = $start.AddSeconds($MaxWaitSeconds)

while ((Get-Date) -lt $deadline) {
    try {
        $result = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Winget ready after $([int]((Get-Date) - $start).TotalSeconds)s"
            exit 0
        }
    } catch { }
    Start-Sleep -Seconds 2
}

Write-Host "Winget not ready after $MaxWaitSeconds seconds"
exit 1

