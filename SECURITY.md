# Política de reporte de vulnerabilidades — RAT Analyzer

## Âmbito

Este repositório inclui componentes que analisam **malware real**. Reporte problemas de segurança de forma responsável.

## O que reportar

- Bypass de autenticação (`RATANALYZER_API_TOKEN`, `VM_AGENT_TOKEN`)
- Path traversal em uploads (backend ou vm-agent)
- Execução de código no host a partir da sandbox
- Exposição de segredos em logs ou artefatos versionados
- Falhas no isolamento da VM (acesso à Internet da guest, escape de snapshot)

## O que **não** reportar

- Scores de risco imprecisos ou falsos positivos YARA (limitação conhecida — heurísticas educativas)
- Ausência de autenticação em modo dev local sem `RATANALYZER_API_TOKEN`
- Driver `proxmox` experimental sem guia de produção

## Como reportar

1. **Não** abra issues públicas com detalhes de exploit.
2. Contacte o mantenedor do projeto (orientador ou autor do repositório) por canal privado.
3. Inclua: componente afetado, passos para reproduzir, impacto estimado, versão/commit.

## Resposta esperada

- Confirmação em **72 h** (dias úteis)
- Correção ou mitigação documentada conforme gravidade
- Crédito no CHANGELOG se desejado

## Boas práticas para utilizadores

- Siga [`docs/SEGURANCA.md`](docs/SEGURANCA.md) e [`docs/production-secrets.md`](docs/production-secrets.md)
- Nunca exponha a API FastAPI nem o vm-agent à Internet sem TLS e firewall
- Execute amostras de malware apenas em VM isolada (Hyper-V)
