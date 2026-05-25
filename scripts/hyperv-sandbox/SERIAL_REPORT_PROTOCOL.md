# Protocolo SBXREP1 — relatórios VM → host via COM1 (Named Pipe)

Este canal é usado pelo sandbox Hyper-V quando `04-Run-Sample.ps1` corre com transporte **Serial** ou **Both** (`_Config.ps1`: `$script:PROJETOVM_ReportTransport`). A VM tem de ser **Generation 1** (COM1 disponível).

## Ligação física (Hyper-V)

1. Com a VM **desligada**, o host executa `Set-VMComPort -Number 1 -Path \\.\pipe\<nome_curto>`.
2. O nome curto do pipe por run é `PVMSBX_<RunId>_<suffixo>` (`<suffixo>` = 12 hex aleatórios no host) — evita colisão com execuções anteriores e `PIPE_BUSY`.
3. Restaurar um **checkpoint** pode repor a configuração da VM guardada no snapshot; o `04` volta a aplicar `Set-VMComPort` **após cada** `Restore-VMSnapshot` e novamente após refresh do snapshot pelo auto-install do Sysmon.

## Formato do fluxo (UTF-8, linhas terminadas em LF `\n`)

Todas as linhas de controlo são texto UTF-8. Os ficheiros são enviados como **blocos binários brutos** imediatamente após a linha `FILE`, com o comprimento exacto indicado.

1. `SBXREP1` — versão do protocolo.
2. `RUN <RunId>` — identificador do run (o mesmo que `-RunId` no host); o receptor valida coincidência se `ExpectedRunId` estiver definido.
3. Zero ou mais pares:
   - Linha: `FILE <nome_lógico> <n_bytes>`
   - `<n_bytes>` bytes brutos (0 permitido).
4. `END` — fim do pacote; o guest fecha a porta.

### Nomes lógicos aceites pelo host neste projecto

| Nome lógico        | Destino no host (por run)        |
|-------------------|-----------------------------------|
| `analysis.txt`    | `D:\PROJETOVM\Reports\analysis_<RunId>.txt` |
| `analysis.json`   | `analysis_<RunId>.json`          |
| `sysmon.jsonl`    | `analysis_<RunId>.sysmon.jsonl`  |
| `sample_stdout.txt` / `sample_stderr.txt` | `*.stdout.txt` / `*.stderr.txt` |

Ficheiros acima de `$script:PROJETOVM_SerialMaxFileBytes` (ex.: `40MB`) não são enviados pelo guest e ficam para **Copy-VMFile** (ex.: `sysmon.jsonl` grande, `trace.etl`).

## Implementação

- **Guest**: `vm\Run-MalwareAnalysis.ps1` — `System.IO.Ports.SerialPort COM1`, função interna `Send-SandboxReportBundleViaCom1`.
- **Host**: `SandboxCommon.psm1` — `Receive-SandboxSerialReportBundle` / `Start-SandboxSerialReportReceiveJob` (processo em background; `Write-Output` do resultado).

## Timeouts

O host inicia o job do pipe **antes** de lançar a análise na VM. O timeout de espera pela **ligação** ao pipe e a duração máxima do job alinham com `GlobalTimeoutSeconds` e `TimeoutSeconds` do run.
