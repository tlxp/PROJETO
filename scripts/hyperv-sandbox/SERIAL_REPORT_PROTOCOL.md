# Protocolo de relatório serial - COM1 → Named Pipe (implementado)

Canal usado pelo pipeline **`04-Run-Sample.ps1`** quando a VM é **Generation 1** e o COM1 está mapeado para `\\.\pipe\<nome>`.

## Ligação física (Hyper-V)

1. Com a VM **desligada**, o host configura `Set-VMComPort -Number 1 -Path \\.\pipe\<PipeShortName>` (ver `SandboxCommon/SerialPipe.ps1` → `Set-SandboxVMComPortPipe`).
2. O nome do pipe por run é `<PROJETOVM_PipeName>_<RunId>` (sanitizado), definido em `RunSample/PhaseA-Setup.ps1`.
3. O **servidor** do pipe é criado pelo **vmwp.exe** quando a VM arranca; o host liga-se como **cliente** (`NamedPipeClientStream`). Ver comentários em `Receive-SandboxReportFromPipe`.

## Formato do fluxo (UTF-8, linhas terminadas em CRLF no guest)

Envio **texto linha-a-linha** - **não** blocos binários `FILE`.

### Guest → host (`vm/Send-ReportViaCom.ps1`)

1. `START_OF_REPORT`
2. Cabeçalho opcional (metadados, uma linha cada):
   - `VERSION=1`
   - `TIMESTAMP=yyyy-MM-dd HH:mm:ss`
   - `SHA256=<hash>` (se disponível)
   - `REPORT_SIZE=<bytes>`
   - `END_HEADER`
3. Corpo: **cada linha do ficheiro de relatório** (`C:\analysis.txt`), uma linha serial de cada vez.
4. `END_OF_REPORT` (ou `END_OF_REPORT_CHECKSUM` - também aceite pelo receptor)

### Host (`SandboxCommon/SerialPipe.ps1`)

Função **`Receive-SandboxReportFromPipe`**:

- Liga-se ao pipe com retries até `TimeoutSeconds`.
- Acumula linhas entre `START_OF_REPORT` e `END_OF_REPORT` / `END_OF_REPORT_CHECKSUM`.
- Grava o resultado em `OutputPath` (ex.: `D:\PROJETOVM\Reports\analysis_<RunId>.txt`).

Job em background: iniciado em `RunSample/PhaseA-Setup.ps1` via `Start-Job` que importa `SandboxCommon.psm1` e chama `Receive-SandboxReportFromPipe`.

## Fallback

Se o pipe expirar ou falhar (`RunSample/PhaseE-WaitReport.ps1`, `PhaseF-CollectResult.ps1`):

- **Copy-VMFile** para `C:\analysis.txt` ou ficheiros já escritos na VM.
- Guest Service Interface ativado só durante o run.

## Timeouts

- Job do pipe: `$TimeoutSeconds + 900` segundos (margem para envio linha-a-linha).
- `-GlobalTimeoutSeconds` no `04-Run-Sample.ps1`: deadline global do run no host.

---

## Especificação futura (não implementada): SBXREP1 binário

Versões antigas deste documento descreviam um protocolo **SBXREP1** com linhas `FILE <nome> <n_bytes>` seguidas de blocos binários brutos e funções `Receive-SandboxSerialReportBundle` / `Start-SandboxSerialReportReceiveJob`. **Esse formato não existe no código atual.** Se for implementado no futuro, deve conviver ou substituir o protocolo linha-a-linha acima.
