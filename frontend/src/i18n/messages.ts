// --- Módulo: messages.ts ---
import type { Lang, Messages } from "./types";

const pt: Messages = {
  appTitle: "RAT Analyzer",
  appSubtitle: "Análise estática de executáveis e DLLs",
  heroTitle: "Analise o seu código",
  heroSubtitle: "Carregue um ficheiro .cs, .dll ou .exe para análise detalhada",
  dropTitle: "Arraste o ficheiro para aqui",
  dropHint: "ou clique para selecionar — .cs, .dll, .exe (máx. 100 MB)",
  dropRemove: "Remover ficheiro selecionado",
  dropSelect: "Selecionar ficheiro para análise",
  fileTypeError: "Tipo de ficheiro não suportado",
  fileTypeErrorDesc: '"{name}" foi rejeitado. Apenas ficheiros {exts} são aceites.',
  fileSizeError: "Ficheiro demasiado grande",
  fileSizeErrorDesc: '"{name}" tem {size} MB. O limite é 100 MB.',
  analysisType: "Tipo de análise:",
  modeStatic: "Apenas estática",
  modeDynamic: "Apenas dinâmica",
  modeBoth: "Ambas",
  analysisLogsTitle: "Logs de análise (desmontagem / descompilação)",
  ghidraProgress: "Progresso Ghidra (pseudo-C)",
  analyze: "Executar Análise",
  analyzing: "A analisar...",
  mockLayout: "Ver layout de teste (mock)",
  stillRunning: "A análise ainda está em execução no backend (estado atual: {status}).",
  stillRunningHint:
    "Volte mais tarde e recarregue esta página — o resultado fica disponível em /analysis/{jobId}.",
  staticLoading: "Análise estática em progresso…",
  staticProcessing: "A processar",
  staticGhidraProgress: "Progresso Ghidra",
  newAnalysis: "Nova Análise",
  results: "Resultados",
  reportVm: "Relatório VM",
  reportStatic: "Relatório estático",
  report: "Relatório",
  loading: "A carregar…",
  obfuscationIndicators: "Indicadores de ofuscação (do relatório)",
  deobfuscation: "Antes / Depois da deobfuscação",
  snippetsJobOnly:
    "Trechos disponíveis apenas quando a análise é aberta através do link do job (?jobId=...).",
  noSnippets: "Nenhuns trechos guardados para este job.",
  snippetsError: "Erro ao obter trechos.",
  cancelled: "Cancelado.",
  unknownStatus: "desconhecido",
  analysisFailed: "Análise falhou no backend.",
  noExternalResult: "Nenhum resultado disponível para o job externo.",
  loadExternalError: "Erro ao carregar resultados externos.",
  noAnalysisResult: "Nenhum resultado disponível na análise.",
  staticRegisterFailed: "Falha ao registar o resultado estático no backend.",
  jobNotFound: "Job de análise não encontrado.",
  analyzeFileError: "Erro ao analisar o ficheiro.",
  apiTimeout: "Timeout ao contactar a API.",
  reportTitleVm: "RELATÓRIO DE ANÁLISE COMPORTAMENTAL — VM SANDBOX",
  reportResumo: "RESUMO",
  reportFileInfo: "INFORMAÇÕES DO FICHEIRO",
  reportRiskScore: "SCORE DE RISCO",
  reportNd: "N/D",
  reportRiskExplain:
    "O score reflecte o comportamento observado na sandbox: processos, registo, rede, ficheiros e persistência.",
  reportRiskInconclusive: "Amostras não executadas ou com timeout ficam marcadas como inconclusivas.",
  reportFiles: "Ficheiros",
  reportProcesses: "Processos",
  reportRegistry: "Registo",
  reportNetwork: "Rede",
  routeHome: "Início",
  routeAnalysis: "Análise",
  routeXref: "Explorador Xref",
  routeResults: "Resultados",
  routePage: "Página",
};

const en: Messages = {
  appTitle: "RAT Analyzer",
  appSubtitle: "Static analysis of executables and DLLs",
  heroTitle: "Analyze your code",
  heroSubtitle: "Upload a .cs, .dll or .exe file for detailed analysis",
  dropTitle: "Drag your file here",
  dropHint: "or click to browse — .cs, .dll, .exe (max. 100 MB)",
  dropRemove: "Remove selected file",
  dropSelect: "Select file for analysis",
  fileTypeError: "Unsupported file type",
  fileTypeErrorDesc: '"{name}" was rejected. Only {exts} files are accepted.',
  fileSizeError: "File too large",
  fileSizeErrorDesc: '"{name}" is {size} MB. The limit is 100 MB.',
  analysisType: "Analysis type:",
  modeStatic: "Static only",
  modeDynamic: "Dynamic only",
  modeBoth: "Both",
  analysisLogsTitle: "Analysis logs (disassembly / decompilation)",
  ghidraProgress: "Ghidra progress (pseudo-C)",
  analyze: "Run Analysis",
  analyzing: "Analyzing...",
  mockLayout: "View test layout (mock)",
  stillRunning: "Analysis is still running on the backend (current status: {status}).",
  stillRunningHint: "Come back later and reload this page — results will be at /analysis/{jobId}.",
  staticLoading: "Static analysis in progress…",
  staticProcessing: "Processing",
  staticGhidraProgress: "Ghidra progress",
  newAnalysis: "New Analysis",
  results: "Results",
  reportVm: "VM report",
  reportStatic: "Static report",
  report: "Report",
  loading: "Loading…",
  obfuscationIndicators: "Obfuscation indicators (from report)",
  deobfuscation: "Before / After deobfuscation",
  snippetsJobOnly: "Snippets are only available when opening analysis via the job link (?jobId=...).",
  noSnippets: "No snippets stored for this job.",
  snippetsError: "Error fetching snippets.",
  cancelled: "Cancelled.",
  unknownStatus: "unknown",
  analysisFailed: "Analysis failed on the backend.",
  noExternalResult: "No result available for the external job.",
  loadExternalError: "Error loading external results.",
  noAnalysisResult: "No result available in the analysis.",
  staticRegisterFailed: "Failed to register static result on the backend.",
  jobNotFound: "Analysis job not found.",
  analyzeFileError: "Error analyzing the file.",
  apiTimeout: "Timeout contacting the API.",
  reportTitleVm: "BEHAVIORAL ANALYSIS REPORT — VM SANDBOX",
  reportResumo: "SUMMARY",
  reportFileInfo: "FILE INFORMATION",
  reportRiskScore: "RISK SCORE",
  reportNd: "N/A",
  reportRiskExplain:
    "The score reflects behavior observed in the sandbox: processes, registry, network, files and persistence.",
  reportRiskInconclusive: "Samples that did not run or timed out are marked inconclusive.",
  reportFiles: "Files",
  reportProcesses: "Processes",
  reportRegistry: "Registry",
  reportNetwork: "Network",
  routeHome: "Home",
  routeAnalysis: "Analysis",
  routeXref: "Xref Explorer",
  routeResults: "Results",
  routePage: "Page",
};

export const CATALOG: Record<Lang, Messages> = { pt, en };

export const STORAGE_KEY = "ratanalyzer-lang";

// --- Normaliza código de idioma para pt ou en ---
export function normalizeLang(value: string | null | undefined): Lang {
  return value === "en" ? "en" : "pt";
}

// --- Lê idioma do parâmetro ?lang= na URL ---
export function readLangFromUrl(): Lang | null {
  if (typeof window === "undefined") return null;
  const q = new URLSearchParams(window.location.search).get("lang");
  return q ? normalizeLang(q) : null;
}

// --- Idioma inicial: URL > localStorage > env ---
export function readInitialLang(): Lang {
  const fromUrl = readLangFromUrl();
  if (fromUrl) return fromUrl;
  if (typeof window !== "undefined") {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) return normalizeLang(stored);
  }
  const env = import.meta.env.VITE_DEFAULT_LOCALE;
  return normalizeLang(typeof env === "string" ? env : null);
}

// --- Substitui placeholders {chave} nas mensagens ---
export function formatMessage(template: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (acc, [key, value]) => acc.replaceAll(`{${key}}`, String(value)),
    template
  );
}
