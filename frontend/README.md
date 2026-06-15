# Drop & Analyze - Interface Web do RAT Analyzer

Interface web para análise de ficheiros executáveis (.exe) e DLLs, integrada com o backend **RAT Analyzer**. Permite arrastar ficheiros, executar análise em tempo real e visualizar relatórios, pseudo-código C e código IL com destaque de indicadores de risco.

Documentação geral: [`docs/README.md`](../docs/README.md) · Segurança: [`docs/production-secrets.md`](../docs/production-secrets.md).

## Funcionalidades

- **Zona de arrastar** - Arraste ficheiros .exe ou .dll para iniciar a análise
- **Modos de análise** - Estática (streaming ou job), dinâmica ou ambas (`useIndexAnalysisSession`)
- **Três painéis** - Relatório de análise, pseudo-C (Ghidra) e código IL com navegação por categorias e funções suspeitas
- **Score de risco** - Nível (CRÍTICO, ALTO, MÉDIO, BAIXO, MUITO BAIXO) e indicadores destacados no código
- **Navegação contextual** - Saltar do relatório para as linhas relevantes no pseudo-C e no IL
- **Assistência Gemini** *(opcional)* - Explicar excertos de pseudo-C com Google Gemini (API key no browser)
- **Trechos ofuscados** - Visualizar ficheiros de excertos obfuscados/deobfuscados quando o backend os gera
- **Acesso por link** - `/?jobId=` ou `/resultados?jobId=` com polling até o job concluir

## Requisitos

- **Node.js** 18+ e **npm**
- Backend **RAT Analyzer** em execução (ver [README principal](../README.md))

## Instalação e execução

```bash
cd frontend
npm i
npm run dev
```

A aplicação abre em **http://localhost:8080** (porta em `vite.config.ts`). Por defeito, a API é
`http://127.0.0.1:8000` (`src/lib/api.ts` se `VITE_API_URL` não estiver definida).

### Configurar URL da API

Crie `.env` na raiz de `frontend` (base: `.env.example`). Quando o backend exige
`RATANALYZER_API_TOKEN`, defina `VITE_API_TOKEN` com o mesmo valor:

```env
VITE_API_URL=http://127.0.0.1:8000
VITE_API_TOKEN=seu-token
```

Em produção: `VITE_API_URL`, `VITE_API_TOKEN` e `npm run build` - ver [`docs/production-secrets.md`](../docs/production-secrets.md).

## Assistência Gemini (opcional)

Funcionalidade **client-side**: o excerto de pseudo-C e a pergunta são enviados **diretamente do browser**
à API Google Gemini. A API key **não** passa pelo backend RAT Analyzer.

1. Nos resultados da análise, abra o painel de código e use **Assistência Gemini**.
2. Introduza a sua [API key do Google AI Studio](https://aistudio.google.com/apikey).
3. A key é guardada em `localStorage` (`rat-analyzer.gemini-api-key`) apenas neste browser.

| Limite | Valor |
|--------|-------|
| Modelo | `gemini-2.0-flash` |
| Excerto de código | 16 000 caracteres (truncagem automática) |
| Pergunta do utilizador | 1 000 caracteres |

**Privacidade:** não envie amostras sensíveis sem rever a política da Google. Para demonstração sem key,
existe modo mock (apenas em layouts de demonstração).

Implementação: `src/lib/gemini.ts`, `src/lib/geminiApiKey.ts`, `src/components/CodePanel/GeminiAssistDialog.tsx`.

## Scripts disponíveis

| Comando | Descrição |
|---------|-----------|
| `npm run dev` | Servidor de desenvolvimento |
| `npm run build` | Build de produção |
| `npm run preview` | Pré-visualizar build de produção |
| `npm run lint` | Verificação ESLint |
| `npm run test` | Testes unitários (Vitest) |
| `npm run test:watch` | Testes em modo watch |

## Tecnologias

- **Vite** · **React 18** · **TypeScript** (strict)
- **Tailwind CSS** + **shadcn/ui** (Radix UI)
- **Framer Motion** · **Lucide React**
- **Vitest** + Testing Library

## Estrutura relevante

```
frontend/
├── src/
│   ├── routes.ts               # Rotas canónicas da SPA (ROUTE_PATTERNS + helpers ROUTES.*)
│   ├── App.tsx                 # Router — usa ROUTE_PATTERNS
│   ├── lib/
│   │   ├── api.ts              # Cliente HTTP (base URL, token, erros)
│   │   ├── analysis.ts         # Normalização de jobs, parsers de relatório
│   │   ├── artifactNaming.ts   # Convenções de nomes de artefatos
│   │   ├── cCodeXref.ts        # Xrefs no pseudo-C
│   │   ├── gemini.ts           # Cliente Gemini (excertos, limites)
│   │   ├── geminiApiKey.ts     # API key em localStorage
│   │   ├── identifiers.ts      # Parsing de identificadores C/IL
│   │   └── utils.ts            # Utilitários partilhados
│   ├── hooks/
│   │   ├── useAnalysisJob.ts
│   │   ├── useAnalysisStream.ts
│   │   ├── useIndexAnalysisSession.ts
│   │   └── useIndexResultsViewModel.ts
│   ├── pages/
│   │   ├── Index.tsx           # Landing + resultados (/ e /analysis/:jobId)
│   │   ├── Index/              # UploadView, AnalysisResultsView, ResultsGrid, …
│   │   ├── ResultadosPage.tsx  # Redirect legado /resultados?jobId=
│   │   ├── XrefExplorerPage.tsx
│   │   └── NotFound.tsx
│   ├── components/
│   │   ├── FileDropZone.tsx
│   │   ├── CodePanel.tsx
│   │   ├── CodePanel/          # GeminiAssistDialog, HighlightedLine, utils
│   │   ├── RouteErrorBoundary.tsx
│   │   ├── GeminiIcon.tsx
│   │   └── ui/                 # shadcn (dialog, sonner, tooltip)
│   └── test/                   # Vitest (routes, api, analysis, gemini, …)
├── .env.example
└── package.json
```

### Rotas

| Path | Componente | Notas |
|------|------------|-------|
| `/` | `Index` | Upload e análise |
| `/analysis/:jobId` | `Index` | Permalink canónico de resultados |
| `/analysis/:jobId/xref` | `XrefExplorerPage` | Explorador xref contextual |
| `/resultados?jobId=` | redirect | Compatibilidade — redireciona para `/analysis/:jobId` |
| `/xref` | `XrefExplorerPage` | Xref sem job (payload em `localStorage`) |

Definições: `src/routes.ts` (`ROUTES`, `ROUTE_PATTERNS`).

## Segurança

Arquitetura completa: [`docs/SEGURANCA.md`](../docs/SEGURANCA.md) · segredos: [`docs/production-secrets.md`](../docs/production-secrets.md).

- Com `RATANALYZER_API_TOKEN` no backend, defina `VITE_API_TOKEN` com o mesmo valor (rebuild obrigatório).
- Relatórios e código são renderizados como **texto** - sem `dangerouslySetInnerHTML`.
- A API key Gemini fica apenas no `localStorage` do browser; não é enviada ao backend do projeto.

## Notas

- Streaming estático: endpoint `/api/analyze_stream` (NDJSON).
- Jobs dinâmicos/ambos: `POST /api/analysis` + polling `GET /api/analysis/{jobId}`.
- Pseudo-C nativo: `pip install --require-hashes -r backend/requirements-ghidra.lock` e `GHIDRA_INSTALL_DIR`.
