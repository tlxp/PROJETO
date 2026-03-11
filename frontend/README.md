# Drop & Analyze — Interface Web do RAT Analyzer

Interface web para análise de ficheiros executáveis (.exe) e DLLs, integrada com o backend **RAT Analyzer**. Permite arrastar ficheiros, executar análise em tempo real e visualizar relatórios, pseudo-código C e código IL com destaque de indicadores de risco.

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

A aplicação abre em `http://localhost:5173` (ou na porta indicada no terminal). Por defeito, a API do backend é `http://localhost:8000`.

### Configurar URL da API

Crie um ficheiro `.env` na raiz de `frontend` (pode usar `.env.example` como base):

```env
# URL da API Python (RAT Analyzer)
VITE_API_URL=http://localhost:8000
```

Em produção, defina `VITE_API_URL` para o URL do seu backend.

## Scripts disponíveis

| Comando        | Descrição                          |
|----------------|------------------------------------|
| `npm run dev`  | Servidor de desenvolvimento        |
| `npm run build`| Build de produção                  |
| `npm run preview` | Pré-visualizar build de produção |
| `npm run lint` | Verificação ESLint                 |
| `npm run test` | Testes com Vitest                  |

## Tecnologias

- **Vite** — Build e dev server
- **React 18** + **TypeScript**
- **Tailwind CSS** + **shadcn/ui** (Radix UI)
- **Framer Motion** — Animações
- **Lucide React** — Ícones
- **React Query** — Estado e cache de dados (se aplicável)

## Estrutura relevante

```
frontend/
├── src/
│   ├── pages/
│   │   └── Index.tsx      # Página principal (drop zone + painéis)
│   ├── components/
│   │   ├── FileDropZone.tsx
│   │   ├── CodePanel.tsx
│   │   └── ui/            # Componentes shadcn
│   └── ...
├── .env.example           # Exemplo de variáveis de ambiente
├── package.json
└── README.md
```

## Notas

- O backend deve expor o endpoint `/api/analyze_stream` para análise em streaming.
- Para pseudo-C de binários nativos, o backend precisa de Ghidra configurado (`GHIDRA_INSTALL_DIR`).
