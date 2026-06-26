# Benign samples — binários inofensivos para validação estática

Cada subpasta contém o código-fonte de um `.exe` publicado em `dist/`.

| Pasta | Executável | Comportamento |
|-------|------------|---------------|
| `hello/` | `BenignHello.exe` | Console mínimo |
| `file-io/` | `BenignFileIo.exe` | Escrita/leitura em `%TEMP%` |
| `http-ms/` | `BenignHttpMs.exe` | HTTP GET a microsoft.com |
| `registry-read/` | `BenignRegistryRead.exe` | Leitura HKCU (sem Run) |
| `crypto-digest/` | `BenignCryptoDigest.exe` | SHA-256 local |
| `env-dump/` | `BenignEnvDump.exe` | Variáveis de ambiente |
| `gui-msg/` | `BenignGuiMsg.exe` | MessageBox WinForms |
| *(benign-vm-test)* | `BenignVmTest.exe` | Cópia do projeto sandbox |

## Compilar

```powershell
.\benign-samples\build.ps1
```

## Avaliação estática (sem execução dos PEs na análise)

```powershell
cd backend
python scripts/run_benign_static_eval.py
```

Saída: `backend/evaluation/benign_static_metrics.json`

Expectativa: nenhum binário deve ser classificado como **ALTO** ou **CRÍTICO**.
