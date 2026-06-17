# Regras YARA - RAT Analyzer

Conjunto heurístico de regras para indicadores em binários **PE Windows**. Versão do conjunto: [`VERSION`](VERSION) (semver do pacote de regras).

Índice: [`docs/README.md`](../docs/README.md) · scoring: `backend/modules/risk_scorer.py` (peso **20** para matches YARA).

## Índice

- [Regras (v2)](#regras-versão-2--jun-2026)
- [Como o scanner usa as regras](#como-o-scanner-usa-as-regras)
- [Falsos positivos](#falsos-positivos)
- [Adicionar uma regra](#adicionar-uma-regra)
- [Testes](#testes)
- [Requisitos do sistema](#requisitos-do-sistema)

## Regras (versão 2 - Jun 2026)

| Ficheiro | Foco | Condição resumida |
|----------|------|-------------------|
| `rat_generic.yar` | RAT nativo | `VirtualAllocEx` + `WriteProcessMemory` + injeção extra + 2 APIs rede + keylog/persistência |
| `c2_patterns.yar` | C&C | TLD suspeito + path beacon **ou** webhook Discord/Telegram **ou** IP:porta + path + POST + Host |
| `stealer.yar` | Stealer | 2 paths de browser + (`CryptUnprotectData`/sqlite + Login Data) **ou** 2 hooks de teclado |
| `evasion.yar` | Evasão | 3 anti-debug + 2 indicadores VM/análise + `Sleep` repetido (>3) |

### Restrições comuns (todas as regras v2)

- Assinatura MZ válida (`uint16(0) == 0x5A4D`)
- `pe.is_pe` e `pe.number_of_sections > 2`
- `filesize < 20MB`

## Como o scanner usa as regras

1. No arranque, `yara_scanner.py` compila todos os `*.yar` desta pasta.
2. Durante a análise estática, cada ficheiro PE é verificado contra o conjunto compilado.
3. Matches são incluídos no relatório e no **risk scorer** (contribuição até 20 pontos no score 0-100).
4. Regras **não** são aplicadas na análise dinâmica (Caminho A/B) - apenas no pipeline estático.

## Falsos positivos

As regras v2 exigem **combinações correlacionadas** (não strings isoladas como `"Discord"` ou `"GET /"`). Mesmo assim, ferramentas de segurança ou instaladores podem ocasionalmente coincidir - trate os matches como **indicadores** a confirmar com análise estática/dinâmica e scoring do pipeline.

## Adicionar uma regra

1. Crie `novo_indicador.yar` nesta pasta.
2. Use `import "pe"` e restrinja a PE + `filesize`.
3. Inclua metadados obrigatórios (validados em CI):

```yara
import "pe"

rule Meu_Indicador
{
    meta:
        description = "Descrição curta do que a regra deteta"
        severity = "high"          // high | medium | low
        author = "RAT Analyzer"
        tags = "tag1 tag2"
        false_positive_risk = "low" // low | medium | high
        date = "2026-06-15"
        version = "1"

    strings:
        $s1 = "exemplo" ascii

    condition:
        uint16(0) == 0x5A4D and
        filesize < 20MB and
        pe.is_pe and
        pe.number_of_sections > 2 and
        $s1
}
```

4. Execute os testes (ver abaixo). O scanner recarrega automaticamente no próximo arranque da API/CLI.

## Testes

```bash
cd backend
python -m pytest tests/test_yara_rules.py -q
```

O CI verifica:

- Compilação de **todos** os `.yar` (requer `yara-python` instalado; testes ignorados se em falta).
- Presença de `meta version`, `pe.is_pe` e `filesize <` em cada ficheiro.
- Pelo menos **4** ficheiros `.yar` no repositório.

## Requisitos do sistema

- **YARA** instalado no sistema (biblioteca usada por `yara-python`) - [releases](https://github.com/VirusTotal/yara/releases).
- Sem YARA: o scanner regista aviso e continua sem matches (pipeline estático não falha).

Afinamento por família de malware requer amostras reais no laboratório - ver roadmap em [`README.md`](../README.md#limitações-e-roadmap).
