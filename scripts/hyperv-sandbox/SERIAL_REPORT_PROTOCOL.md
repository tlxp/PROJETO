# Protocolo de transferência de relatório — PsDirect + SHA256

Canal usado pelo pipeline **`04-Run-Sample.ps1`**: o guest grava o relatório em disco e o host **copia** o ficheiro via **PowerShell Direct** ou **Copy-VMFile** (Guest Services), com **verificação SHA256 após a cópia**.

> **Histórico:** versões anteriores enviavam o relatório por **COM1 → Named Pipe** (`Send-ReportViaCom.ps1`). Esse transporte foi **removido**; o código legado (`SandboxCommon/SerialPipe.ps1`, `02-Host-ReceiveReport.ps1`) permanece apenas para referência/debug.

## Fluxo resumido

1. Guest executa `vm/Run-MalwareAnalysis.ps1` → grava `C:\analysis.txt` e `C:\analysis.json`.
2. Guest escreve marcador `REPORT_END;` e cria `C:\analysis_work\guest_analysis_done.txt` com metadados (incl. **SHA256**).
3. Host (`RunSample/PhaseE-WaitReport.ps1`) faz polling até `guest_analysis_done.txt` ou `REPORT_END;`.
4. Host copia `C:\analysis.txt` com `Try-ReceiveSandboxGuestReport` (`SandboxCommon/VmFileTransfer.ps1`).
5. Host calcula SHA256 do ficheiro copiado e compara com o digest do guest; em caso de falha, **apaga** o ficheiro no host.

## Ficheiro de conclusão no guest (`guest_analysis_done.txt`)

JSON compacto (UTF-8), escrito por `Run-MalwareAnalysis.ps1` após o relatório estar fechado:

| Campo | Descrição |
|-------|-----------|
| `finishedUtc` | Timestamp ISO 8601 (UTC) |
| `reportPath` | Caminho do relatório (ex.: `C:\analysis.txt`) |
| `reportSha256` | SHA256 do ficheiro de relatório **no guest** |
| `reportBytes` | Tamanho em bytes |
| `jsonReportPath` | Caminho do JSON (ex.: `C:\analysis.json`) |
| `pid` | PID do processo de análise |
| `phaseError` | Erro de fase, se existir |
| `transport` | `"psdirect"` |

## Validação no host (após cópia)

Funções em `SandboxCommon/VmFileTransfer.ps1`:

- **`Get-SandboxGuestReportDigest`** — lê `reportSha256` / `reportBytes` do `guest_analysis_done.txt` ou recalcula no guest.
- **`Assert-SandboxCopiedReportHash`** — compara tamanho e SHA256 do ficheiro no host.
- **`Assert-FileSha256`** — em `SandboxCommon/Hashing.ps1`.

Regras:

- Relatórios **completos** (`REPORT_END;` ou `guest_analysis_done.txt`): verificação **obrigatória** quando o guest fornece hash.
- Cópias **parciais** (crash/stall): verificação só se o guest tiver digest e o relatório estiver marcado como completo.

Destino no host: `D:\PROJETOVM\Reports\analysis_<RunId>.txt`.

O JSON do run (`run_<RunId>.json`) inclui `report_sha256` e `report_hash_verified`.

## Modos de cópia

`Copy-SandboxVMFileFromGuest` escolhe automaticamente:

1. **PsDirect** (chunks Base64) — quando `Copy-VMFile -FileSource Guest` não está disponível no Hyper-V instalado.
2. **Copy-VMFile Guest** — quando o cmdlet suporta `FileSource Guest`; Guest Service Interface ativado só durante o run.

## Timeouts

- Espera do relatório: `$TimeoutSeconds` da amostra + ~1500 s de overhead de análise (`RunSample/PhaseA-Setup.ps1`).
- `-GlobalTimeoutSeconds` no `04-Run-Sample.ps1`: deadline global do run no host (estendido para amostras grandes).

## Especificações não implementadas

- Protocolo **SBXREP1** binário (`FILE <nome> <n_bytes>`).
- Envio linha-a-linha **COM1** (`START_OF_REPORT` … `END_OF_REPORT`).
