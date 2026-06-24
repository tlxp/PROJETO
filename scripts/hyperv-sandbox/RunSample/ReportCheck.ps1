# --- Script: ReportCheck.ps1 ---
# --- Verificação de relatório, logging e diagnóstico do guest ---
# *carregado via dot-sourcing no mesmo scope do orquestrador*

# --- Função: Test-ReportLooksComplete ---
# *confirma que o relatório contém cabeçalho e rodapé gerados por Run-MalwareAnalysis.ps1*
function Test-ReportLooksComplete {
    param([string] $Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -le 0) { return $false }
        $txt = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($txt)) { return $false }
        if ($txt -notmatch "RELAT") { return $false }
        if ($txt -notmatch "FIM DO RELAT") { return $false }
        return $true
    } catch {
        return $false
    }
}

# --- Função: Add-LogLine ---
# *acrescenta linha com timestamp ao ficheiro de log do host*
function Add-LogLine { param([string]$Path, [string]$Value) Add-Content -Path $Path -Value "[$(Get-Date -Format 'HH:mm:ss')] $Value" }

# --- Função: Get-SandboxGuestAnalysisDiag ---
# *consulta remotamente o estado da análise dentro da VM via PowerShell Direct*
function Get-SandboxGuestAnalysisDiag {
    param(
        [Parameter(Mandatory = $true)][string] $VMName,
        [Parameter(Mandatory = $true)][pscredential] $Credential,
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [string] $ReportPath = "C:\analysis.txt",
        [string] $ReportEndMarker = "REPORT_END;",
        [int] $PidToCheck = 0
    )

    return Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
        param($WorkDirLocal, $ReportPathLocal, $ReportEndMarkerLocal, $PidToCheckLocal)
        $out = [ordered]@{
            doneFile     = $false
            aliveFile    = $false
            reportBytes  = 0
            reportComplete = $false
            launchError  = ''
            launchOk     = $null
            com1LogTail  = ''
            crashLogTail = ''
            pidRunning   = $false
        }

        # *caminhos de ficheiros de estado criados pela análise no guest*
        $donePath = Join-Path $WorkDirLocal 'guest_analysis_done.txt'
        $alivePath = Join-Path $WorkDirLocal 'guest_alive.txt'
        $errPath = Join-Path $WorkDirLocal 'launch_error.txt'
        $statusPath = Join-Path $WorkDirLocal 'launch_status.json'
        $com1LogPath = Join-Path $WorkDirLocal 'com1_send.log'
        $crashLogPath = Join-Path $WorkDirLocal 'analysis_crash.log'

        $out.doneFile = Test-Path -LiteralPath $donePath
        $out.aliveFile = Test-Path -LiteralPath $alivePath
        if (Test-Path -LiteralPath $ReportPathLocal) {
            $out.reportBytes = [long](Get-Item -LiteralPath $ReportPathLocal).Length
        }
        if (Test-Path -LiteralPath $errPath) {
            $out.launchError = (Get-Content -LiteralPath $errPath -TotalCount 5 -ErrorAction SilentlyContinue) -join ' | '
        }
        if (Test-Path -LiteralPath $statusPath) {
            try {
                $st = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $st.ok) { $out.launchOk = [bool]$st.ok }
            } catch { }
        }
        if (Test-Path -LiteralPath $com1LogPath) {
            $out.com1LogTail = (Get-Content -LiteralPath $com1LogPath -Tail 3 -ErrorAction SilentlyContinue) -join ' | '
        }
        if (Test-Path -LiteralPath $crashLogPath) {
            $out.crashLogTail = (Get-Content -LiteralPath $crashLogPath -Tail 3 -ErrorAction SilentlyContinue) -join ' | '
        }

        # *verifica se o marcador REPORT_END; está no final do relatório*
        if ($out.reportBytes -gt 0) {
            try {
                $markerBytes = [System.Text.Encoding]::UTF8.GetBytes($ReportEndMarkerLocal)
                $scan = [Math]::Max($markerBytes.Length, 8192)
                $fs = [System.IO.File]::Open($ReportPathLocal, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $len = $fs.Length
                    $readLen = [int][Math]::Min($scan, $len)
                    $null = $fs.Seek($len - $readLen, [System.IO.SeekOrigin]::Begin)
                    $buf = New-Object byte[] $readLen
                    $n = $fs.Read($buf, 0, $readLen)
                    if ($n -gt 0) {
                        $tail = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
                        $out.reportComplete = $tail.Contains($ReportEndMarkerLocal)
                    }
                } finally {
                    $fs.Dispose()
                }
            } catch { }
        }
        if ($PidToCheckLocal -gt 0) {
            $out.pidRunning = $null -ne (Get-Process -Id $PidToCheckLocal -ErrorAction SilentlyContinue)
        }
        [pscustomobject]$out
    } -ArgumentList $WorkDir, $ReportPath, $ReportEndMarker, $PidToCheck -ErrorAction Stop
}
