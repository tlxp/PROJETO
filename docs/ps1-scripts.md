# Scripts PowerShell — encoding e idioma

## Encoding

| Regra | Detalhe |
|-------|---------|
| **Charset** | UTF-8 com BOM (`utf-8-sig`) em todos os `.ps1` sob `scripts/` |
| **Fim de linha** | CRLF (`\r\n`) — ver `.editorconfig` secção `[*.ps1]` |
| **CI** | `python scripts/ci/check_ps1_utf8.py` (job GitHub Actions) |

### Ferramentas

```bash
# Validar UTF-8 (sem escrever)
python scripts/ci/check_ps1_utf8.py

# Normalizar acentos PT + BOM + CRLF
python scripts/ci/normalize_ps1_pt.py

# Ver o que mudaria
python scripts/ci/normalize_ps1_pt.py --check
```

## Idioma

| Contexto | Idioma |
|----------|--------|
| Mensagens ao utilizador (`Write-Host`, `throw`, `Write-Warning`) | **Português (PT)** com acentos correctos |
| Comentários de implementação / nomes de funções | PT ou EN técnico (consistente no ficheiro) |
| Identificadores (`$VMName`, `Assert-SandboxVmNetworkIsolation`) | Inglês (convenção PowerShell) |
| Saída de relatórios na VM guest | PT (alinhado com analistas) |

Evitar formas sem acento (`nao`, `configuracao`, `servico`) em texto voltado ao utilizador — usar `não`, `configuração`, `serviço`.

## Excepções

- `scripts/hyperv-sandbox/tools/winutil.ps1` — script de terceiros (não versionado; `.gitignore`).
- Strings que reproduzem saída literal de ferramentas externas (ex.: mensagens em inglês do Windows/ADK).

## Hyper-V sandbox

Documentação operacional: [`scripts/hyperv-sandbox/README.md`](../scripts/hyperv-sandbox/README.md).
