// --- Módulo: messages.ts ---
// Catálogo de mensagens da UI (PT e EN).

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
  stubBannerTitle: "Análise dinâmica simulada",
  stubBannerConfigured:
    "A amostra não será executada. O backend está com SANDBOX_VM_DRIVER=stub — os resultados comportamentais são placeholders de desenvolvimento. Configure hyperv/proxmox ou use o WPF (Caminho B) para execução real.",
  stubBannerResult:
    "Este relatório foi gerado sem executar a amostra (driver stub). Não use processos, rede, registo ou scores VM para conclusões de segurança.",
  stubConfirmTitle: "Sandbox real não configurada",
  stubConfirmBody:
    "O backend está em modo stub: a amostra não será executada e o relatório dinâmico será simulado. Deseja continuar?",
  stubConfirmContinue: "Continuar (simulado)",
  stubConfirmStaticOnly: "Só análise estática",
  stubConfirmCancel: "Cancelar",
  stubVmNotExecuted: "— (não executado)",
  stubReportTitle: "RELATÓRIO DINÂMICO — MODO SIMULADO (STUB)",
  stubReportHeadline:
    "A amostra NÃO foi executada. Este relatório existe apenas para validar o fluxo da API.",
  stubReportSample: "Amostra",
  stubReportEvidence: "Evidência comportamental:",
  stubReportNa: "N/A — amostra não executada",
  stubReportNoScore:
    "Score VM: indisponível — não há dados de execução. Não interprete ausência de deteções como benignidade.",
  stubReportNote: "Nota do sistema:",
  stubReportConfigure:
    "Para execução real: defina SANDBOX_VM_DRIVER=hyperv (ou proxmox) no backend, ou use a análise dinâmica via WPF (Caminho B).",
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
  stubBannerTitle: "Simulated dynamic analysis",
  stubBannerConfigured:
    "The sample will not be executed. The backend uses SANDBOX_VM_DRIVER=stub — behavioral results are development placeholders. Configure hyperv/proxmox or use the WPF client (Path B) for real execution.",
  stubBannerResult:
    "This report was generated without executing the sample (stub driver). Do not use VM processes, network, registry or scores for security conclusions.",
  stubConfirmTitle: "Real sandbox not configured",
  stubConfirmBody:
    "The backend is in stub mode: the sample will not run and the dynamic report will be simulated. Continue?",
  stubConfirmContinue: "Continue (simulated)",
  stubConfirmStaticOnly: "Static analysis only",
  stubConfirmCancel: "Cancel",
  stubVmNotExecuted: "— (not executed)",
  stubReportTitle: "DYNAMIC REPORT — SIMULATED MODE (STUB)",
  stubReportHeadline:
    "The sample was NOT executed. This report only validates the API workflow.",
  stubReportSample: "Sample",
  stubReportEvidence: "Behavioral evidence:",
  stubReportNa: "N/A — sample not executed",
  stubReportNoScore:
    "VM score: unavailable — no execution data. Do not treat missing detections as benign.",
  stubReportNote: "System note:",
  stubReportConfigure:
    "For real execution: set SANDBOX_VM_DRIVER=hyperv (or proxmox) on the backend, or use dynamic analysis via WPF (Path B).",
};

export const CATALOG: Record<Lang, Messages> = { pt, en };

export const STORAGE_KEY = "ratanalyzer-lang";

// --- Resolução de idioma ---
export function normalizeLang(value: string | null | undefined): Lang {
  return value === "en" ? "en" : "pt";
}

export function readLangFromUrl(): Lang | null {
  if (typeof window === "undefined") return null;
  const q = new URLSearchParams(window.location.search).get("lang");
  return q ? normalizeLang(q) : null;
}

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

export function formatMessage(template: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (acc, [key, value]) => acc.replaceAll(`{${key}}`, String(value)),
    template
  );
}
