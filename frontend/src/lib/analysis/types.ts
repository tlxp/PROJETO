// --- Módulo: types.ts ---
// Tipos de domínio da análise (resultados, relatório, painéis).

// --- Tipos de domínio ---
// *Resultados, categorias do relatório, capítulos e snippets de deobfuscação*

export type FlaggedFunction = {
  name: string;
  id?: string;
  startLine: number;
  endLine: number;
  indicators?: string[];
  score?: number;
  scoreRaw?: number;
  severity?: string;
  reasons?: string[];
};

export type AnalysisResult = {
  report: string;
  cCode: string;
  ilCode: string;
  fileName: string;
  riskScore: number;
  riskLevel: string;
  // *Indicadores que deram flag para highlight no pseudo-C (vindo do backend)*
  flaggedIndicators?: string[];
  // *Resumo opcional de análise dinâmica*
  dynamicSummary?: string | null;
  // *Relatório textual ou JSON da VM (Caminho A via backend ou Caminho B via WPF)*
  vmReport?: string | null;
  // *True quando a análise dinâmica foi simulada (driver stub) — amostra não executada*
  dynamicSimulated?: boolean;
  // *True quando a análise dinâmica está em curso mas o relatório ainda não chegou*
  dynamicPending?: boolean;
  // *True quando a análise estática está em curso mas o relatório ainda não chegou*
  staticPending?: boolean;
  // *Progresso Ghidra (0–100) publicado pelo WPF durante análise estática*
  staticProgress?: number | null;
  // *Funções suspeitas com ranges exatos no pseudo-C (vindo do backend)*
  flaggedFunctions?: FlaggedFunction[];
  // *Caminho do ficheiro com trechos obfuscados extraídos*
  obfuscatedSnippetsFile?: string;
  // *Caminho do ficheiro com trechos deobfuscados*
  obfuscatedSnippetsDeobfuscatedFile?: string;
  // *Número de indicadores de ofuscação (categoria Obfuscation do relatório)*
  obfuscationIndicatorCount?: number;
};

export type AnalysisMode = "static" | "dynamic" | "both";

export type ExpandedPanel = "c" | "il" | "report" | "report-static" | "report-vm" | null;

export type ReportCategory = {
  // *Linha de resumo, ex.: "Suspicious Imports: 3 ocorrências = 15/15 pontos"*
  label: string;
  // *ID estável para guardar o offset de navegação*
  id: string;
  // *Linha do relatório onde o resumo aparece*
  summaryLineIndex: number;
  // *Linhas de código associadas a esta categoria (ocorrências)*
  lineNumbers: number[];
};

export type ReportChapter = {
  label: string;
  line: number;
};
