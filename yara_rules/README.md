# Regras YARA — RAT Analyzer

Conjunto heurístico de regras para indicadores em binários **PE Windows**.
Carregadas por `backend/modules/yara_scanner.py` a partir desta pasta (fonte única).

> **Auditoria (Jun 2026):** regras v2 endurecidas (combinações correlacionadas) — ver [`docs/AUDITORIA.md`](../docs/AUDITORIA.md).

## Regras (versão 2 — Jun 2026)

| Ficheiro | Foco | Condição resumida |
|----------|------|-------------------|
| `rat_generic.yar` | RAT nativo | `VirtualAllocEx` + `WriteProcessMemory` + injeção extra + 2 APIs rede + keylog/persistência |
| `c2_patterns.yar` | C&C | TLD suspeito + path beacon **ou** webhook Discord/Telegram **ou** IP:porta + path + POST + Host |
| `stealer.yar` | Stealer | 2 paths de browser + (`CryptUnprotectData`/sqlite + Login Data) **ou** 2 hooks de teclado |
| `evasion.yar` | Evasão | 3 anti-debug + 2 indicadores VM/análise + `Sleep` repetido (>3) |

Todas exigem: MZ válido, `pe.is_pe`, `filesize < 20MB`.

## Falsos positivos

As regras v2 exigem **combinações correlacionadas** (não strings isoladas como `"Discord"` ou `"GET /"`).
Mesmo assim, ferramentas de segurança ou instaladores podem ocasionalmente coincidir — trate os matches como **indicadores** a confirmar com análise estática/dinâmica e scoring do pipeline.

## Testes

```bash
cd backend && python -m pytest tests/test_yara_rules.py -q
```

## Personalização

Adicione `.yar` nesta pasta; o scanner compila todos no arranque.
Documente `false_positive_risk`, `version` e `date` nos metadados de cada regra.
