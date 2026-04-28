<#
.SYNOPSIS
    Servidor no host que recebe o relatório da VM via Named Pipe (porta serial virtual).
    Versão melhorada com handshake, verificação de integridade e logging detalhado.
.DESCRIPTION
    Abre o pipe \\.\pipe\SandboxReportPipe e grava as linhas recebidas em D:\PROJETOVM\Reports\.
    Implementa protocolo de comunicação robusto:
      - Handshake inicial
      - Receção em chunks com verificação
      - Checksum SHA256
      - Confirmação de receção
      - Timeout configurável
.PARAMETER PipeName
    Nome do pipe (deve coincidir com Set-VMComPort no setup).
.PARAMETER OutputPath
    Ficheiro .txt onde gravar o relatório. Se não indicado, usa D:\PROJETOVM\Reports\analysis_<timestamp>.txt
.PARAMETER TimeoutSeconds
    Tempo máximo à espera da primeira ligação e entre leituras.
.EXAMPLE
    .\02-Host-ReceiveReport.ps1 -OutputPath "D:\PROJETOVM\Reports\analysis_001.txt"
#>

param(
    [string] $PipeName = "",
    [string] $OutputPath = "",
    [int]    $TimeoutSeconds = 600,
    [switch] $Verbose
)

# Carregar módulo
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

# Carregar configuração
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
if ([string]::IsNullOrWhiteSpace($PipeName)) { $PipeName = $script:PROJETOVM_PipeName }
$ReportsDir = $script:PROJETOVM_ReportsPath
Ensure-DirectoryExists -Path $ReportsDir

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $ReportsDir "analysis_$timestamp.txt"
}

Write-Host "========================================"
Write-Host "RECEPTOR DE RELATÓRIO VIA COM1 (Melhorado)"
Write-Host "========================================"
Write-Host "Pipe: $PipeName"
Write-Host "Output: $OutputPath"
Write-Host "Timeout: $TimeoutSeconds s"
Write-Host ""

# Variáveis para logging
$logFile = $OutputPath -replace "\.txt$", "_receive.log"
$startTime = Get-Date

function Write-ReceiveLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp][$Level] $Message"
    Write-Host $logLine
    Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Calculate-SHA256 {
    param([string]$Content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $hashBytes = $sha256.ComputeHash($bytes)
    return ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Receive-ReportWithProtocol {
    param(
        [System.IO.Pipes.NamedPipeServerStream] $Pipe,
        [int] $TimeoutSeconds
    )
    
    $reader = $null
    $lines = New-Object System.Collections.Generic.List[string]
    $metadata = @{}
    $bodyChunks = New-Object System.Collections.Generic.List[byte[]]
    $inBody = $false
    $expectedChecksum = $null
    $reportContent = $null
    
    try {
        $reader = New-Object System.IO.StreamReader($pipe)
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        
        # 1. Aguardar handshake
        Write-ReceiveLog "A aguardar handshake..."
        $handshake = ReadLineWithTimeout -Reader $reader -Deadline $deadline
        if ($handshake -ne "SANDBOX_REPORT_START") {
            throw "Handshake inválido: '$handshake'"
        }
        
        # Enviar ACK
        $pipe.Write([System.Text.Encoding]::UTF8.GetBytes("READY`r`n"))
        $pipe.Flush()
        Write-ReceiveLog "Handshake recebido e confirmado"
        
        # 2. Processar cabeçalho
        while ($true) {
            $line = ReadLineWithTimeout -Reader $reader -Deadline $deadline
            if ($line -eq $null) { throw "Timeout à espera de linha do cabeçalho" }
            if ($line -eq "ENDHEADER") { break }
            
            if ($line -match "^(HEADER)$") {
                # Ignorar linha HEADER
                continue
            }
            
            if ($line -match "^(version|sample_sha256|report_size|checksum|chunk_size|timestamp)=(.+)$") {
                $metadata[$Matches[1]] = $Matches[2]
                Write-ReceiveLog "Metadado: $($Matches[1]) = $($Matches[2])"
            }
        }
        
        # Validar metadados
        if (-not $metadata.ContainsKey("checksum")) {
            throw "Checksum não encontrado no cabeçalho"
        }
        $expectedChecksum = $metadata["checksum"]
        
        # Confirmar cabeçalho
        $pipe.Write([System.Text.Encoding]::UTF8.GetBytes("HEADER_OK`r`n"))
        $pipe.Flush()
        Write-ReceiveLog "Cabeçalho validado, a aguardar corpo"
        
        # 3. Receber corpo em chunks
        $line = ReadLineWithTimeout -Reader $reader -Deadline $deadline
        if ($line -ne "BODY_START") { throw "Esperado BODY_START, recebido '$line'" }
        
        $pipe.Write([System.Text.Encoding]::UTF8.GetBytes("BODY_READY`r`n"))
        $pipe.Flush()
        
        $chunkCount = 0
        $bodyBytes = New-Object System.Collections.Generic.List[byte]
        
        while ($true) {
            $line = ReadLineWithTimeout -Reader $reader -Deadline $deadline
            if ($line -eq $null) { throw "Timeout à espera de chunk" }
            if ($line -eq "BODY_END") { break }
            
            if ($line -match "^CHUNK:(\d+):(.+)$") {
                $chunkNum = [int]$Matches[1]
                $chunkBase64 = $Matches[2]
                
                try {
                    $chunkData = [Convert]::FromBase64String($chunkBase64)
                    $bodyBytes.AddRange($chunkData)
                    $chunkCount++
                    
                    if ($chunkCount % 10 -eq 0) {
                        Write-ReceiveLog "Recebidos $chunkCount chunks (total: $($bodyBytes.Count) bytes)"
                    }
                } catch {
                    throw "Erro ao decodificar chunk ${chunkNum}: $_"
                }
            } else {
                Write-ReceiveLog "Linha inesperada: '$line'"
            }
        }
        
        Write-ReceiveLog "Corpo recebido: $chunkCount chunks, $($bodyBytes.Count) bytes"
        
        # Confirmar corpo
        $pipe.Write([System.Text.Encoding]::UTF8.GetBytes("BODY_OK`r`n"))
        $pipe.Flush()
        
        # 4. Verificar checksum
        $reportContent = [System.Text.Encoding]::UTF8.GetString($bodyBytes.ToArray())
        $calculatedChecksum = Calculate-SHA256 -Content $reportContent
        
        Write-ReceiveLog "Checksum esperado: $expectedChecksum"
        Write-ReceiveLog "Checksum calculado: $calculatedChecksum"
        
        if ($calculatedChecksum -ne $expectedChecksum) {
            throw "Checksum inválido! Corrompido durante transmissão."
        }
        
        # 5. Aguardar checksum final (opcional, por compatibilidade)
        $finalLine = ReadLineWithTimeout -Reader $reader -Deadline $deadline
        if ($finalLine -and $finalLine -match "^CHECKSUM=") {
            $finalChecksum = $finalLine -replace "^CHECKSUM=", ""
            if ($finalChecksum -ne $expectedChecksum) {
                Write-ReceiveLog "AVISO: Checksum final não coincide" "WARN"
            }
        }
        
        # Confirmar conclusão
        $pipe.Write([System.Text.Encoding]::UTF8.GetBytes("COMPLETE`r`n"))
        $pipe.Flush()
        
        Write-ReceiveLog "REPORT RECEIVED SUCCESSFULLY - Checksum validado"
        return $reportContent
        
    } catch {
        Write-ReceiveLog "Erro durante receção: $_" "ERROR"
        throw
    }
}

function ReadLineWithTimeout {
    param(
        [System.IO.StreamReader] $Reader,
        [DateTime] $Deadline
    )
    
    $line = ""
    while ([DateTime]::UtcNow -lt $Deadline) {
        if ($Reader.Peek() -ge 0) {
            $line = $Reader.ReadLine()
            if ($line -ne $null) {
                return $line.Trim()
            }
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

try {
    Write-ReceiveLog "A iniciar servidor Named Pipe: $PipeName"
    $pipe = $null
    $receivedContent = $null
    
    # Tentar como servidor primeiro, com fallback para cliente
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Write-ReceiveLog "Tentativa ${attempt}: a criar servidor pipe..."
            $pipe = New-SandboxNamedPipeServer -PipeName $PipeName
            
            if ($Verbose) {
                Write-ReceiveLog "Pipe server criado, à espera de ligação..." "VERBOSE"
            }
            
            # Aguardar ligação da VM
            $pipe.WaitForConnection()
            Write-ReceiveLog "VM ligada ao pipe"
            
            # Receber relatório
            $receivedContent = Receive-ReportWithProtocol -Pipe $pipe -TimeoutSeconds $TimeoutSeconds
            break
            
        } catch {
            Write-ReceiveLog "Falha na tentativa ${attempt}: $_" "WARN"
            if ($pipe) { try { $pipe.Dispose() } catch { } }
            $pipe = $null
            
            if ($attempt -eq 3) {
                Write-ReceiveLog "Todas as tentativas falharam" "ERROR"
                throw "Não foi possível estabelecer ligação após 3 tentativas"
            }
            
            Start-Sleep -Seconds 2
        }
    }
    
    if ($receivedContent) {
        # Gravar relatório
        [System.IO.File]::WriteAllText($OutputPath, $receivedContent, [System.Text.Encoding]::UTF8)
        
        $lineCount = ($receivedContent -split "`r`n").Count
        $duration = [int]((Get-Date) - $startTime).TotalSeconds
        
        Write-ReceiveLog ""
        Write-ReceiveLog "========================================"
        Write-ReceiveLog "RELATÓRIO RECEBIDO COM SUCESSO!"
        Write-ReceiveLog "========================================"
        Write-ReceiveLog "Output: $OutputPath"
        Write-ReceiveLog "Linhas: $lineCount"
        Write-ReceiveLog "Tamanho: $($receivedContent.Length) bytes"
        Write-ReceiveLog "Duração: ${duration}s"
        Write-ReceiveLog "Log: $logFile"
        
        # Criar relatório JSON de confirmação
        $confirmation = @{
            received_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            output_path = $OutputPath
            line_count = $lineCount
            size_bytes = $receivedContent.Length
            duration_seconds = $duration
            status = "success"
        }
        $jsonPath = $OutputPath -replace "\.txt$", "_receipt.json"
        $confirmation | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8
        
        exit 0
    }
    
} catch {
    Write-ReceiveLog "ERRO FATAL: $_" "ERROR"
    
    # Criar relatório de erro
    $errorReport = @{
        error = $_.Exception.Message
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        pipe_name = $PipeName
        output_path = $OutputPath
        log_file = $logFile
    }
    $errorJsonPath = $OutputPath -replace "\.txt$", "_error.json"
    $errorReport | ConvertTo-Json | Set-Content -Path $errorJsonPath -Encoding UTF8
    
    exit 1
}