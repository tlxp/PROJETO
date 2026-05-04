<#
.SYNOPSIS
    Envia o ficheiro de relatório para o host via porta COM1 (serial virtual -> Named Pipe).
    Versão SIMPLIFICADA e ROBUSTA - sem handshake complexo.
#>

param(
    [string] $ReportPath = "C:\analysis.txt",
    [string] $SampleHash = "",
    [int]    $MaxRetries = 3,
    [int]    $BaudRate = 115200,    # Mais rápido, mantendo fiabilidade no NamedPipe
    [int]    $DelayMs = 0           # Em Named Pipe não é necessário "throttle" por linha
)

function Write-SerialLine {
    param(
        [System.IO.Ports.SerialPort] $Port,
        [string] $Line,
        [int] $DelayMs
    )
    $Port.WriteLine($Line)
    # Flush ajuda bastante no caminho COM1->NamedPipe (Hyper-V)
    try { $Port.BaseStream.Flush() } catch { }
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Send-ReportSimple {
    param(
        [string] $ReportPath,
        [string] $SampleHash,
        [int] $Attempt
    )
    
    Write-Host "[INFO] Tentativa $Attempt de $MaxRetries"
    
    if (-not (Test-Path $ReportPath)) {
        throw "Ficheiro não encontrado: $ReportPath"
    }
    
    # Ler o relatório
    $content = Get-Content -Path $ReportPath -Encoding UTF8 -Raw
    $lines = $content -split "`r`n"
    
    # Calcular checksum simples (para verificação)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
    $checksum = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
    
    $port = $null
    try {
        # Abrir porta serial
        $port = New-Object System.IO.Ports.SerialPort "COM1", $BaudRate, None, 8, One
        $port.ReadTimeout = 5000
        $port.WriteTimeout = 5000
        $port.NewLine = "`r`n"
        $port.Open()
        
        Write-Host "[INFO] COM1 aberta (baud: $BaudRate)"
        
        # Aguardar 1 segundo para estabilizar
        Start-Sleep -Milliseconds 200
        
        # Enviar um marcador de início simples
        Write-SerialLine -Port $port -Line "START_OF_REPORT" -DelayMs 0
        
        # Enviar cabeçalho básico
        Write-SerialLine -Port $port -Line "VERSION=1" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -DelayMs $DelayMs
        if ($SampleHash -and $SampleHash.Trim().Length -gt 0) {
            Write-SerialLine -Port $port -Line "SHA256=$SampleHash" -DelayMs $DelayMs
        }
        Write-SerialLine -Port $port -Line "REPORT_SIZE=$($content.Length)" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "CHECKSUM=$checksum" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "END_HEADER" -DelayMs 0
        
        # Enviar corpo linha por linha
        $lineCount = 0
        foreach ($line in $lines) {
            Write-SerialLine -Port $port -Line $line -DelayMs $DelayMs
            $lineCount++
            if ($lineCount % 50 -eq 0) {
                Write-Host "[PROGRESS] $lineCount linhas enviadas"
            }
        }
        
        # Enviar marcador de fim
        Write-SerialLine -Port $port -Line "END_OF_REPORT" -DelayMs $DelayMs
        Write-SerialLine -Port $port -Line "CHECKSUM=$checksum" -DelayMs 0
        
        Start-Sleep -Milliseconds 150
        
        Write-Host "[SUCCESS] Relatório enviado: $lineCount linhas, $($content.Length) bytes"
        return $true
        
    } catch {
        Write-Warning "[ERROR] $($_.Exception.Message)"
        return $false
    } finally {
        if ($port -and $port.IsOpen) {
            try { $port.Close() } catch { }
            Write-Host "[INFO] COM1 fechada"
        }
    }
}

# Executar com retry
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