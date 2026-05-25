<#
.SYNOPSIS
    Envia o ficheiro de relatório para o host via porta COM1 (serial virtual -> Named Pipe).
    Versão SIMPLIFICADA e ROBUSTA - sem handshake complexo.
#>

param(
    [string] $ReportPath = "C:\analysis.txt",
    [string] $SampleHash = "",
    [int]    $MaxRetries = 3,
    [int]    $BaudRate = 115200,
    [int]    $DelayMs = 0
)

function Write-ComLog {
    param([string] $Message)
    $ts = (Get-Date).ToUniversalTime().ToString("o")
    $cn = $env:COMPUTERNAME
    Write-Host "[COM1 guest=$cn utc=$ts] $Message"
}

function Write-SerialLine {
    param(
        [System.IO.Ports.SerialPort] $Port,
        [string] $Line,
        [int] $DelayMs
    )
    $Port.WriteLine($Line)
    try { $Port.BaseStream.Flush() } catch { }
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Send-ReportSimple {
    param(
        [string] $ReportPath,
        [string] $SampleHash,
        [int] $Attempt
    )

    if (-not (Test-Path $ReportPath)) {
        throw "Ficheiro não encontrado: $ReportPath"
    }
    $lenRep = (Get-Item -LiteralPath $ReportPath).Length
    Write-ComLog "Tentativa $Attempt/$MaxRetries report=$ReportPath bytes=$lenRep"

    $content = Get-Content -Path $ReportPath -Encoding UTF8 -Raw
    # CRLF ou só LF (ficheiros gerados com line endings Unix); Environment.NewLine falha se o ficheiro for só \n
    $lines = $content -split '\r?\n'

    $port = $null
    try {
        Write-ComLog "A abrir SerialPort COM1 baud=$BaudRate"
        $port = New-Object System.IO.Ports.SerialPort "COM1", $BaudRate, None, 8, One
        $port.Encoding = New-Object System.Text.UTF8Encoding($false)
        $port.ReadTimeout = 5000
        $port.WriteTimeout = 5000
        $port.NewLine = "`r`n"
        $port.Open()
        Write-ComLog "COM1 Open OK; a enviar cabecalho SBXREP1 ($($lines.Count) linhas corpo)"
        Start-Sleep -Milliseconds 200

        Write-SerialLine -Port $port -Line "START_OF_REPORT" -DelayMs 0
        Write-ComLog "START_OF_REPORT enviado"

        # Cabeçalho opcional
        Write-SerialLine -Port $port -Line "VERSION=1" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -DelayMs $DelayMs
        if ($SampleHash -and $SampleHash.Trim().Length -gt 0) {
            Write-SerialLine -Port $port -Line "SHA256=$SampleHash" -DelayMs $DelayMs
        }
        Write-SerialLine -Port $port -Line "REPORT_SIZE=$($content.Length)" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "END_HEADER" -DelayMs 0

        $lineCount = 0
        foreach ($line in $lines) {
            Write-SerialLine -Port $port -Line $line -DelayMs $DelayMs
            $lineCount++
            if ($lineCount % 50 -eq 0) {
                Write-Host "[PROGRESS] $lineCount linhas enviadas"
            }
        }

        Write-SerialLine -Port $port -Line "END_OF_REPORT" -DelayMs $DelayMs
        Write-ComLog "END_OF_REPORT enviado; a fechar porta"

        Start-Sleep -Milliseconds 150
        Write-ComLog "Fim envio OK lineCount=$lineCount bytes=$($content.Length)"
        Write-Host "[SUCCESS] Relatório enviado: $lineCount linhas, $($content.Length) bytes"
        return $true

    } catch {
        Write-ComLog "ERRO: $($_.Exception.Message)"
        Write-Warning "[ERROR] $($_.Exception.Message)"
        return $false
    } finally {
        if ($port -and $port.IsOpen) {
            try { $port.Close() } catch { }
            Write-Host "[INFO] COM1 fechada"
            Write-ComLog "COM1 Close"
        }
    }
}

for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    if (Send-ReportSimple -ReportPath $ReportPath -SampleHash $SampleHash -Attempt $attempt) {
        Write-Host ""
        Write-Host "========================================="
        Write-Host "RELATORIO ENVIADO COM SUCESSO VIA COM1"
        Write-Host "========================================="
        exit 0
    }

    if ($attempt -lt $MaxRetries) {
        $waitTime = 5
        Write-Host "[INFO] A aguardar $waitTime segundos..."
        Start-Sleep -Seconds $waitTime
    }
}

Write-Error "Falha ao enviar relatório após $MaxRetries tentativas"
exit 1
