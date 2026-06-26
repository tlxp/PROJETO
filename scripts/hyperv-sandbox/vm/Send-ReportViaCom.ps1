# --- Módulo: Send-ReportViaCom.ps1 ---
# --- Envio do relatório via porta COM1/pipe ---
<#

.SYNOPSIS

    Envia o ficheiro de relatório para o host via porta COM1 (serial virtual -> Named Pipe).

#>



param(

    [string] $ReportPath = "C:\analysis.txt",

    [string] $SampleHash = "",

    [int]    $MaxRetries = 5,

    [int]    $BaudRate = 115200,

    [int]    $DelayMs = 0,

    [int]    $HostReadyDelayMs = 2500

)



# --- Logging de operações COM1 ---
function Write-ComLog {

    param([string] $Message)

    $ts = (Get-Date).ToUniversalTime().ToString("o")

    $cn = $env:COMPUTERNAME

    $line = "[COM1 guest=$cn utc=$ts] $Message"

    Write-Host $line

    try {

        $logPath = "C:\analysis_work\com1_send.log"

        $dir = Split-Path -Parent $logPath

        if ($dir -and -not (Test-Path -LiteralPath $dir)) {

            New-Item -ItemType Directory -Path $dir -Force | Out-Null

        }

        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue

    } catch { }

}



# --- Escrita de uma linha na porta serial ---
function Write-SerialLine {

    param(

        [System.IO.Ports.SerialPort] $Port,

        [string] $Line,

        [int] $DelayMs

    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Line + "`r`n")

    $Port.Write($bytes, 0, $bytes.Length)

    try { $Port.BaseStream.Flush() } catch { }

    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

}



# --- Abertura da porta COM1 com tentativas ---
function Open-Com1Port {

    param(

        [int] $BaudRate,

        [int] $MaxOpenTries = 8

    )



    $portName = "COM1"

    $availablePorts = @([System.IO.Ports.SerialPort]::GetPortNames())

    Write-ComLog "Portas seriais detectadas: $($availablePorts -join ', ')"



    if ($availablePorts.Count -gt 0 -and ($availablePorts -notcontains $portName)) {

        Write-ComLog "AVISO: $portName ausente na enumeração; a tentar abrir na mesma (Hyper-V COM virtual)."

    }



    $lastErr = ""

    for ($openTry = 1; $openTry -le $MaxOpenTries; $openTry++) {

        $port = $null

        try {

            $port = New-Object System.IO.Ports.SerialPort $portName, $BaudRate, None, 8, One

            $port.Encoding = New-Object System.Text.UTF8Encoding($false)

            $port.ReadTimeout = 5000

            $port.WriteTimeout = 60000

            $port.NewLine = "`r`n"

            $port.Handshake = [System.IO.Ports.Handshake]::None

            $port.DtrEnable = $true

            $port.RtsEnable = $true

            # Atraso progressivo entre tentativas de abertura
            Start-Sleep -Milliseconds (400 * $openTry)

            $port.Open()

            Write-ComLog "COM1 Open OK (tentativa $openTry/$MaxOpenTries baud=$BaudRate)"

            return $port

        } catch {

            $lastErr = $_.Exception.Message

            Write-ComLog "Open tentativa $openTry/$MaxOpenTries falhou: $lastErr"

            if ($port) {

                try { if ($port.IsOpen) { $port.Close() } } catch { }

                try { $port.Dispose() } catch { }

            }

            if ($openTry -lt $MaxOpenTries) { Start-Sleep -Milliseconds (500 * $openTry) }

        }

    }

    throw "Não foi possível abrir $portName após $MaxOpenTries tentativas: $lastErr"

}



# --- Envio do relatório linha a linha via COM1 ---
function Send-ReportSimple {

    param(

        [string] $ReportPath,

        [string] $SampleHash,

        [int] $Attempt

    )



    if (-not (Test-Path -LiteralPath $ReportPath)) {

        throw "Ficheiro não encontrado: $ReportPath"

    }

    $lenRep = (Get-Item -LiteralPath $ReportPath).Length

    Write-ComLog "Tentativa $Attempt/$MaxRetries report=$ReportPath bytes=$lenRep"



    $content = Get-Content -Path $ReportPath -Encoding UTF8 -Raw

    $lines = $content -split '\r?\n'



    $port = $null

    try {

        $port = Open-Com1Port -BaudRate $BaudRate



        # Aguarda estabilização do par virtual COM1<->pipe e receptor no host

        Write-ComLog "A aguardar ${HostReadyDelayMs}ms antes do envio (host receptor COM1)"

        Start-Sleep -Milliseconds $HostReadyDelayMs



        Write-SerialLine -Port $port -Line "COM1_PING" -DelayMs 100

        Start-Sleep -Milliseconds 200

        Write-SerialLine -Port $port -Line "START_OF_REPORT" -DelayMs 100

        Write-ComLog "START_OF_REPORT enviado"



        # Cabeçalho do protocolo de transferência
        Write-SerialLine -Port $port -Line "VERSION=1" -DelayMs $DelayMs

        Write-SerialLine -Port $port -Line "TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -DelayMs $DelayMs

        if ($SampleHash -and $SampleHash.Trim().Length -gt 0) {

            Write-SerialLine -Port $port -Line "SHA256=$SampleHash" -DelayMs $DelayMs

        }

        Write-SerialLine -Port $port -Line "REPORT_SIZE=$($content.Length)" -DelayMs $DelayMs

        Write-SerialLine -Port $port -Line "END_HEADER" -DelayMs 50



        $lineCount = 0

        foreach ($line in $lines) {

            Write-SerialLine -Port $port -Line $line -DelayMs $DelayMs

            $lineCount++

            if ($lineCount % 50 -eq 0) {

                Write-Host "[PROGRESS] $lineCount linhas enviadas"

            }

        }



        Write-SerialLine -Port $port -Line "END_OF_REPORT" -DelayMs 200

        Write-ComLog "END_OF_REPORT enviado; a drenar buffer"

        Start-Sleep -Milliseconds 500

        Write-ComLog "Fim envio OK lineCount=$lineCount bytes=$($content.Length)"

        Write-Host "[SUCCESS] Relatório enviado: $lineCount linhas, $($content.Length) bytes"

        return $true



    } catch {

        $ports = @([System.IO.Ports.SerialPort]::GetPortNames()) -join ', '

        Write-ComLog "ERRO: $($_.Exception.Message) (portas=$ports)"

        Write-Warning "[ERROR] $($_.Exception.Message)"

        return $false

    } finally {

        if ($port) {

            try { if ($port.IsOpen) { $port.Close() } } catch { }

            try { $port.Dispose() } catch { }

            Write-ComLog "COM1 Close"

        }

    }

}



# --- Loop de tentativas com backoff ---
for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

    if (Send-ReportSimple -ReportPath $ReportPath -SampleHash $SampleHash -Attempt $attempt) {

        Write-Host ""

        Write-Host "========================================="

        Write-Host "RELATORIO ENVIADO COM SUCESSO VIA COM1"

        Write-Host "========================================="

        exit 0

    }



    if ($attempt -lt $MaxRetries) {

        # Espera crescente entre tentativas falhadas
        $waitTime = [Math]::Min(15, 3 * $attempt)

        Write-Host "[INFO] A aguardar $waitTime segundos antes de retry COM1..."

        Start-Sleep -Seconds $waitTime

    }

}



Write-Error "Falha ao enviar relatório após $MaxRetries tentativas"

exit 1
