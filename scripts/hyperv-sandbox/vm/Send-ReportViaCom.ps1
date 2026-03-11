<#
.SYNOPSIS
    Envia o ficheiro de relatório para o host via porta COM1 (serial virtual -> Named Pipe).
.DESCRIPTION
    A executar DENTRO da VM após a análise. O host deve ter 02-Host-ReceiveReport.ps1
    a correr a escuta no pipe correspondente.
    Envia um pequeno protocolo:
      HEADER / pares chave=valor / ENDHEADER / corpo do relatório / CHECKSUM=<sha256>
.PARAMETER ReportPath
    Caminho do ficheiro .txt do relatório (ex.: C:\analysis.txt).
.PARAMETER SampleHash
    Hash SHA256 da amostra (opcional, para incluir no cabeçalho).
#>
param(
    [string] $ReportPath = "C:\analysis.txt",
    [string] $SampleHash = ""
)

if (-not (Test-Path $ReportPath)) {
    Write-Error "Ficheiro não encontrado: $ReportPath"
    exit 1
}

try {
    $lines = Get-Content -Path $ReportPath -Encoding UTF8
    $bodyText = ($lines -join "`n")
    $reportSize = $bodyText.Length

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
    $hashBytes = $sha256.ComputeHash($bytes)
    $checksum = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    $port = New-Object System.IO.Ports.SerialPort "COM1", 9600, None, 8, One
    $port.Open()

    # Cabeçalho com metadados
    $port.WriteLine("HEADER")
    $port.WriteLine("version=1")
    if ($SampleHash -and $SampleHash.Trim().Length -gt 0) {
        $port.WriteLine("sample_sha256=$SampleHash")
    }
    $port.WriteLine("report_size=$reportSize")
    $port.WriteLine("ENDHEADER")

    # Corpo do relatório
    foreach ($line in $lines) {
        $port.WriteLine($line)
    }

    # Checksum final
    $port.WriteLine("CHECKSUM=$checksum")

    $port.Close()
    Write-Host "Relatório enviado via COM1 com cabeçalho e checksum."
}
catch {
    Write-Error $_
    exit 1
}
