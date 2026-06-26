// --- Módulo: vite-env.d.ts ---
// Tipos das variáveis de ambiente Vite.

/// <reference types="vite/client" />

interface ImportMetaEnv {
  // *URL base da API do backend (RAT Analyzer); default: http://localhost:8000*
  readonly VITE_API_URL?: string;
  // *token opcional quando o backend exige RATANALYZER_API_TOKEN*
  readonly VITE_API_TOKEN?: string;
  // *true para mostrar o botão de layout mock em dev (ver mockDemoEnabled.ts)*
  readonly VITE_ENABLE_MOCK_DEMO?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
