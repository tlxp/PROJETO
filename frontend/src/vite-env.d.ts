// --- Módulo: vite-env.d.ts ---
/// <reference types="vite/client" />

interface ImportMetaEnv {
  // *URL base da API do backend (RAT Analyzer); default: http://localhost:8000*
  readonly VITE_API_URL?: string;
  // *token opcional quando o backend exige RATANALYZER_API_TOKEN*
  readonly VITE_API_TOKEN?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
