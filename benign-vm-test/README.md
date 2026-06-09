# Benign VM Test

Programa **inofensivo** em .NET 8, usado apenas para **validar a sandbox e o formato dos relatórios** da
análise dinâmica, sem recorrer a malware real. Faz parte do ecossistema do
[RAT Analyzer](../README.md).

> **Importante:** este programa **não é malicioso**. Apenas reproduz, de forma controlada e reversível,
> alguns comportamentos típicos que os monitores da sandbox devem detetar.

## O que faz

Ao executar, gera artefactos observáveis para confirmar que a monitorização da VM os capta:

- **Ficheiros** — cria/modifica `C:\analysis_work\benign_test_marker.txt`.
- **Registry** — escreve chaves em `HKCU\Software\RATAnalyzerTest`.
- **Processos** — inicia um processo filho (`cmd.exe`) que escreve `C:\analysis_work\child_process.txt`.

Estes três sinais correspondem às categorias monitorizadas pelo fluxo da sandbox (ver
[`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md)).

## Compilar

```powershell
cd benign-vm-test
dotnet build -c Release
```

Para gerar um executável autónomo para a arquitetura da VM (x86 ou x64):

```powershell
dotnet publish -c Release -r win-x64 --self-contained false
```

## Usar na sandbox

1. Compile o executável (acima).
2. Copie-o para a VM (ou para `D:\PROJETOVM\Samples\`).
3. Execute uma análise apontando para este `.exe` (ver
   [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md) ou
   [`docs/sandbox-hyperv-setup.md`](../docs/sandbox-hyperv-setup.md)).
4. Confirme que o relatório lista as alterações de ficheiros, registry e o processo filho acima.

## Estrutura

```
benign-vm-test/
├── Program.cs            # Lógica do teste (ficheiros, registry, processo filho)
├── BenignVmTest.csproj   # Projeto .NET 8
└── README.md
```
