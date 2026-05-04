# Benign VM Test (não-malicioso)

Este programa é **inofensivo** e existe apenas para validar a sandbox/relatórios.

## O que ele faz

- Cria/modifica o ficheiro: `C:\analysis_work\benign_test_marker.txt`
- Escreve chaves em: `HKCU\Software\RATAnalyzerTest`
- Inicia um processo filho (`cmd.exe`) que escreve: `C:\analysis_work\child_process.txt`

## Como compilar (exemplo)

Podes criar um projeto console e substituir o `Program.cs` por este ficheiro.
Depois compilar para x86 ou x64 conforme a tua VM.

