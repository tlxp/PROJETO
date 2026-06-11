# Drop & Analyze — Interface Web do RAT Analyzer

Interface web para análise de ficheiros executáveis (.exe) e DLLs, integrada com o backend **RAT Analyzer**. Permite arrastar ficheiros, executar análise em tempo real e visualizar relatórios, pseudo-código C e código IL com destaque de indicadores de risco.

Estado da auditoria: [`docs/AUDITORIA.md`](../docs/AUDITORIA.md) (Jun 2026 — concluída).

## Funcionalidades

- **Zona de arrastar** — Arraste ficheiros .exe ou .dll para iniciar a análise
- **Análise em streaming** — Progresso em tempo real e atualização incremental dos resultados
- **Três painéis** — Relatório de análise, pseudo-C (Ghidra) e código IL com navegação por categorias e funções suspeitas
- **Score de risco** — Exibição do nível de risco (CRÍTICO, ALTO, MÉDIO, BAIXO, MUITO BAIXO) e indicadores destacados no código
- **Navegação contextual** — Saltar do relatório para as linhas relevantes no pseudo-C e no IL

## Requisitos

- **Node.js** 18+ e **npm**
- Backend **RAT Analyzer** em execução (ver [README principal](../README.md))

## Instalação e execução

```bash
# Na pasta do frontend
cd frontend

# Instalar dependências
npm i

# Iniciar servidor de desenvolvimento (com recarregamento automático)
npm run dev
```

A aplicação abre em **http://localhost:8080** (porta definida em `vite.config.ts`). Por defeito, a API do backend é `http://127.0.0.1:8000` (fallback em `src/lib/api.ts` se `VITE_API_URL` não estiver definida).

### Configurar URL da API

Crie um ficheiro `.env` na raiz de `frontend` (pode usar `.env.example` como base):

```env
# URL da API Python (RAT Analyzer)
VITE_API_URL=http://127.0.0.1:8000

# Obrigatório quando o backend exige RATANALYZER_API_TOKEN (mesmo valor)
# VITE_API_TOKEN=seu-token
```

Em produção, defina `VITE_API_URL` e `VITE_API_TOKEN` (ver [`docs/production-secrets.md`](../docs/production-secrets.md)).

## Scripts disponíveis

| Comando        | Descrição                          |
|----------------|------------------------------------|
| `npm run dev`  | Servidor de desenvolvimento        |
| `npm run build`| Build de produção                  |
| `npm run preview` | Pré-visualizar build de produção |
| `npm run lint` | Verificação ESLint                 |
| `npm run test` | Testes unitários (Vitest)           |
| `npm run test:watch` | Testes em modo watch        |

## Tecnologias

- **Vite** — Build e dev server
- **React 18** + **TypeScript**
- **Tailwind CSS** + **shadcn/ui** (Radix UI)
- **Framer Motion** — Animações
- **Lucide React** — Ícones

## Estrutura relevante

```
frontend/
├── src/
│   ├── lib/
│   │   ├── api.ts           # Cliente HTTP (base URL, timeout, erros)
│   │   ├── analysis.ts      # Normalização de jobs, parsers de relatório
│   │   ├── cCodeXref.ts     # Sessão de xrefs no pseudo-C
│   │   └── artifactNaming.ts
│   ├── hooks/
│   │   ├── useAnalysisJob.ts           # Polling de jobs (AbortController)
│   │   ├── useAnalysisStream.ts        # Streaming NDJSON
│   │   ├── useIndexAnalysisSession.ts  # Sessão de upload/análise na página Index
│   │   └── useIndexResultsViewModel.ts # Estado da grelha de resultados
│   ├── pages/
│   │   ├── Index.tsx            # Orquestrador (~75 linhas)
│   │   └── Index/               # IndexHeader, AnalysisResultsView, UploadView, …
│   ├── components/
│   │   ├── FileDropZone.tsx
│   │   ├── CodePanel.tsx
│   │   ├── RouteErrorBoundary.tsx  # Error boundary por rota
│   │   └── ui/                  # shadcn (dialog, tooltip, sonner)
│   └── test/                    # 29 testes Vitest
├── .env.example
├── package.json
└── README.md
```

## Segurança

- Com `RATANALYZER_API_TOKEN` no backend, defina `VITE_API_TOKEN` com o mesmo valor (rebuild obrigatório).
- O output de análise é renderizado como texto — **não** usar `dangerouslySetInnerHTML` em conteúdo de relatórios.

## Notas

- O backend deve expor o endpoint `/api/analyze_stream` para análise em streaming.
- Para pseudo-C de binários nativos: `pip install --require-hashes -r backend/requirements-ghidra.lock` e `GHIDRA_INSTALL_DIR`.
