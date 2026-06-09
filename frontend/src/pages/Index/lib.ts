import { API_BASE } from "./constants";

export type AnalysisResult = {
  report: string;
  cCode: string;
  ilCode: string;
  fileName: string;
  riskScore: number;
  riskLevel: string;
  /** Indicadores (funções/strings) que deram flag para highlight no pseudo-C (vindo do backend). */
  flaggedIndicators?: string[];
  /** Resumo opcional de análise dinâmica (quando existir). */
  dynamicSummary?: string | null;
  /** Funções suspeitas com ranges exatos no pseudo-C (vindo do backend). */
  flaggedFunctions?: {
    name: string;
    id?: string;
    startLine: number;
    endLine: number;
    indicators?: string[];
    score?: number;
    scoreRaw?: number;
    severity?: string;
    reasons?: string[];
  }[];
  /** Caminho do ficheiro com trechos obfuscados extraídos (quando existir). */
  obfuscatedSnippetsFile?: string;
  /** Caminho do ficheiro com trechos deobfuscados (quando existir). */
  obfuscatedSnippetsDeobfuscatedFile?: string;
  /** Número de indicadores de ofuscação (corresponde à categoria Obfuscation do relatório). */
  obfuscationIndicatorCount?: number;
};

export type AnalysisMode = "static" | "dynamic" | "both";

export type ErrorResponse = { detail?: unknown };
export type ValidationDetailItem = { msg?: unknown };

export function stringifyDetail(detail: unknown): string {
  if (detail == null) return "";
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((d) => {
        if (typeof d === "string") return d;
        if (d && typeof d === "object" && "msg" in d) {
          const msg = (d as ValidationDetailItem).msg;
          return typeof msg === "string" ? msg : JSON.stringify(msg);
        }
        return JSON.stringify(d);
      })
      .join(", ");
  }
  try {
    return JSON.stringify(detail);
  } catch {
    return String(detail);
  }
}

export function readErrorDetail(res: Response, fallbackText: string): Promise<string> {
  return res
    .json()
    .catch(() => ({ detail: fallbackText } satisfies ErrorResponse))
    .then((msg: ErrorResponse) => stringifyDetail(msg?.detail) || fallbackText);
}

export function asRecord(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
}

export type ExpandedPanel = "c" | "il" | "report" | null;

export type ReportFlag = {
  label: string;
  line?: number;
  reportLineIndex?: number;
};

export type ReportCategory = {
  /** Linha de resumo, ex.: "Suspicious Imports: 3 ocorrências = 15/15 pontos" */
  label: string;
  /** ID estável para guardar o offset de navegação. */
  id: string;
  /** Linha do relatório onde o resumo aparece. */
  summaryLineIndex: number;
  /** Linhas de código associadas a esta categoria (ocorrências). */
  lineNumbers: number[];
};

export type ReportChapter = {
  label: string;
  line: number;
};

/** Constrói um AnalysisResult a partir do payload de um job da API /api/analysis. */
export function buildAnalysisResultFromJob(job: unknown, fallbackFileName?: string): AnalysisResult | null {
  const fj = asRecord(job);
  if (!fj) return null;

  let staticResult: unknown = fj.staticResult ?? null;
  const dynamicResult = fj.dynamicResult ?? null;

  // Em alguns caminhos (ex.: histórico em SQLite) staticResult pode vir como string JSON.
  if (staticResult && typeof staticResult === "string") {
    try {
      staticResult = JSON.parse(staticResult);
    } catch {
      staticResult = null;
    }
  }

  if (staticResult && typeof staticResult === "object") {
    const sr = asRecord(staticResult) ?? {};
    const dr = dynamicResult && typeof dynamicResult === "object" ? asRecord(dynamicResult) : null;
    return {
      report: typeof sr.report === "string" ? sr.report : "",
      cCode: typeof sr.cCode === "string" ? sr.cCode : "",
      ilCode: typeof sr.ilCode === "string" ? sr.ilCode : "",
      fileName: typeof sr.fileName === "string" ? sr.fileName : fallbackFileName ?? "output",
      riskScore: typeof sr.riskScore === "number" ? sr.riskScore : 0,
      riskLevel: typeof sr.riskLevel === "string" ? sr.riskLevel : "",
      flaggedIndicators: Array.isArray(sr.flaggedIndicators)
        ? (sr.flaggedIndicators as unknown[]).filter((x): x is string => typeof x === "string")
        : [],
      flaggedFunctions: Array.isArray(sr.flaggedFunctions)
        ? (sr.flaggedFunctions as unknown[]).filter((x): x is Record<string, unknown> => !!x && typeof x === "object").map((f) => {
            const rf = asRecord(f) ?? {};
            return {
              name: typeof rf.name === "string" ? rf.name : "",
              id: typeof rf.id === "string" ? rf.id : undefined,
              startLine: typeof rf.startLine === "number" ? rf.startLine : 0,
              endLine: typeof rf.endLine === "number" ? rf.endLine : 0,
              indicators: Array.isArray(rf.indicators)
                ? (rf.indicators as unknown[]).filter((x): x is string => typeof x === "string")
                : [],
              score: typeof rf.score === "number" ? rf.score : undefined,
              scoreRaw: typeof rf.scoreRaw === "number" ? rf.scoreRaw : undefined,
              severity: typeof rf.severity === "string" ? rf.severity : undefined,
              reasons: Array.isArray(rf.reasons)
                ? (rf.reasons as unknown[]).filter((x): x is string => typeof x === "string")
                : [],
            };
          })
        : [],
      dynamicSummary: dr && typeof dr.dynamicSummary === "string" ? dr.dynamicSummary : null,
      obfuscatedSnippetsFile: typeof sr.obfuscatedSnippetsFile === "string" ? sr.obfuscatedSnippetsFile : undefined,
      obfuscatedSnippetsDeobfuscatedFile: typeof sr.obfuscatedSnippetsDeobfuscatedFile === "string" ? sr.obfuscatedSnippetsDeobfuscatedFile : undefined,
      obfuscationIndicatorCount: typeof sr.obfuscationIndicatorCount === "number" ? sr.obfuscationIndicatorCount : undefined,
    };
  }

  if (dynamicResult && typeof dynamicResult === "object") {
    const dr = asRecord(dynamicResult) ?? {};
    const dynamicSummary =
      typeof dr.dynamicSummary === "string" ? dr.dynamicSummary : "Análise dinâmica concluída.";
    const behaviorStr =
      dr.dynamicReport != null ? JSON.stringify(dr.dynamicReport, null, 2) : "";
    return {
      report: `# Análise dinâmica\n\n${dynamicSummary}\n\n${behaviorStr}`,
      cCode: "",
      ilCode: "",
      fileName: fallbackFileName ?? "output",
      riskScore: 0,
      riskLevel: "",
      flaggedIndicators: [],
      dynamicSummary,
    };
  }

  // Fallback: alguns payloads antigos podem trazer campos diretos no root.
  if (typeof fj.report === "string" || typeof fj.cCode === "string" || typeof fj.ilCode === "string") {
    return {
      report: typeof fj.report === "string" ? fj.report : "",
      cCode: typeof fj.cCode === "string" ? fj.cCode : "",
      ilCode: typeof fj.ilCode === "string" ? fj.ilCode : "",
      fileName: typeof fj.fileName === "string" ? fj.fileName : fallbackFileName ?? "output",
      riskScore: typeof fj.riskScore === "number" ? fj.riskScore : 0,
      riskLevel: typeof fj.riskLevel === "string" ? fj.riskLevel : "",
      flaggedIndicators: Array.isArray(fj.flaggedIndicators)
        ? (fj.flaggedIndicators as unknown[]).filter((x): x is string => typeof x === "string")
        : [],
      flaggedFunctions: Array.isArray(fj.flaggedFunctions)
        ? (fj.flaggedFunctions as unknown[]).filter((x): x is Record<string, unknown> => !!x && typeof x === "object").map((f) => {
            const rf = asRecord(f) ?? {};
            return {
              name: typeof rf.name === "string" ? rf.name : "",
              id: typeof rf.id === "string" ? rf.id : undefined,
              startLine: typeof rf.startLine === "number" ? rf.startLine : 0,
              endLine: typeof rf.endLine === "number" ? rf.endLine : 0,
              indicators: Array.isArray(rf.indicators)
                ? (rf.indicators as unknown[]).filter((x): x is string => typeof x === "string")
                : [],
              score: typeof rf.score === "number" ? rf.score : undefined,
              scoreRaw: typeof rf.scoreRaw === "number" ? rf.scoreRaw : undefined,
              severity: typeof rf.severity === "string" ? rf.severity : undefined,
              reasons: Array.isArray(rf.reasons)
                ? (rf.reasons as unknown[]).filter((x): x is string => typeof x === "string")
                : [],
            };
          })
        : [],
      dynamicSummary: null,
      obfuscatedSnippetsFile: typeof fj.obfuscatedSnippetsFile === "string" ? fj.obfuscatedSnippetsFile : undefined,
      obfuscatedSnippetsDeobfuscatedFile: typeof fj.obfuscatedSnippetsDeobfuscatedFile === "string" ? fj.obfuscatedSnippetsDeobfuscatedFile : undefined,
    };
  }

  return null;
}

export async function publishStaticAnalysisResult(result: AnalysisResult): Promise<string> {
  const res = await fetch(`${API_BASE}/api/analysis/upload_static`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      fileName: result.fileName,
      report: result.report,
      cCode: result.cCode,
      ilCode: result.ilCode,
      riskScore: result.riskScore,
      riskLevel: result.riskLevel,
      flaggedIndicators: result.flaggedIndicators ?? [],
      flaggedFunctions: result.flaggedFunctions ?? [],
    }),
  });
  if (!res.ok) {
    const text = await readErrorDetail(res, res.statusText);
    throw new Error(text || "Falha ao publicar resultado estático no backend.");
  }
  const data = (await res.json()) as { jobId?: string };
  if (!data.jobId) {
    throw new Error("Resposta inesperada ao publicar resultado estático (jobId em falta).");
  }
  return data.jobId;
}

/** Encontra blocos top-level no código C por matching de chavetas (funções ou blocos). */
export function getCBlocks(code: string): { start: number; end: number }[] {
  const lines = code.split("\n");
  const blocks: { start: number; end: number }[] = [];
  let balance = 0;
  let blockStart = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const open = (line.match(/\{/g) || []).length;
    const close = (line.match(/\}/g) || []).length;
    const prev = balance;
    balance += open - close;
    if (prev === 0 && balance >= 1) blockStart = i + 1;
    if (prev === 1 && balance === 0) {
      blocks.push({ start: blockStart, end: i + 1 });
    }
  }
  return blocks;
}

/** Junta intervalos sobrepostos ou adjacentes. */
export function mergeRanges(ranges: { start: number; end: number }[]): { start: number; end: number }[] {
  if (ranges.length === 0) return [];
  const sorted = [...ranges].sort((a, b) => a.start - b.start);
  const out: { start: number; end: number }[] = [sorted[0]];
  for (let i = 1; i < sorted.length; i++) {
    const cur = sorted[i];
    const last = out[out.length - 1];
    if (cur.start <= last.end + 1) {
      last.end = Math.max(last.end, cur.end);
    } else {
      out.push(cur);
    }
  }
  return out;
}

/** Devolve o bloco (função) que contém a linha dada. */
export function getBlockContainingLine(
  code: string,
  lineNumber: number
): { start: number; end: number } | null {
  const blocks = getCBlocks(code);
  for (const block of blocks) {
    if (lineNumber >= block.start && lineNumber <= block.end) return block;
  }
  return null;
}

/** Calcula que intervalos do código C mostrar a partir de funções suspeitas. */
export function getCDisplayRanges(
  cCode: string,
  flaggedFunctions: { startLine: number; endLine: number }[] | undefined | null
): { start: number; end: number }[] | undefined {
  if (!flaggedFunctions || flaggedFunctions.length === 0) return undefined;
  const ranges = flaggedFunctions
    .map((f) => ({
      start: Math.max(1, f.startLine),
      end: Math.max(f.startLine, f.endLine),
    }))
    .filter((r) => r.start <= r.end);
  if (ranges.length === 0) return undefined;
  return mergeRanges(ranges);
}

/** Estatísticas de uma palavra selecionada no código (menções, tipo inferido, funções). */
export type WordStats = {
  mentions: number;
  inferredType: string | null;
  functionsCount: number;
  maliciousCount: number;
};

export function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function getWordStats(
  code: string,
  word: string,
  maliciousRanges: { start: number; end: number }[] | undefined
): WordStats {
  if (!word || word.length < 2) {
    return { mentions: 0, inferredType: null, functionsCount: 0, maliciousCount: 0 };
  }
  const escaped = escapeRegex(word);
  const re = new RegExp("\\b" + escaped + "\\b", "g");
  const mentions = (code.match(re) || []).length;

  const lines = code.split("\n");
  let inferredType: string | null = null;

  // 1) Declaração C: tipo + palavra (int x, void foo, ...)
  const cTypeRe = new RegExp(
    "\\b(int|void|char|long|short|float|double|bool|unsigned|size_t|uint\\w*|struct\\s+\\w+)\\s+" + escaped + "\\b"
  );
  for (const line of lines) {
    const m = cTypeRe.exec(line);
    if (m) {
      inferredType = m[1].trim().replace(/\s+/g, " ");
      break;
    }
  }

  // 2) Declaração C#/.NET: string, var, List<>, etc. + palavra
  if (!inferredType) {
    const csTypeRe = new RegExp(
      "\\b(string|var|bool|int|long|float|double|object|byte|sbyte|ushort|uint|ulong|decimal)\\s+" + escaped + "\\b"
    );
    for (const line of lines) {
      const m = csTypeRe.exec(line);
      if (m) {
        inferredType = m[1];
        break;
      }
    }
  }

  // 3) Parâmetro: ( tipo palavra ) ou , tipo palavra, ou ) palavra )
  if (!inferredType) {
    const paramRe = new RegExp(
      "[,(]\\s*(?:const\\s+)?(?:int|void|char|long|short|float|double|bool|unsigned|string|var)\\s+" + escaped + "\\s*[),]",
      "i"
    );
    if (paramRe.test(code)) inferredType = "parâmetro";
  }

  // 4) Chamada: palavra( -> função
  if (!inferredType && new RegExp("\\b" + escaped + "\\s*\\(").test(code)) {
    inferredType = "função";
  }

  // 5) Acesso membro: .palavra ou ->palavra (campo/propriedade)
  if (!inferredType && new RegExp("[.->]\\s*" + escaped + "\\b").test(code)) {
    inferredType = "campo/propriedade";
  }

  // 6) Ponteiro C: * palavra ou palavra *
  if (!inferredType && new RegExp("\\*\\s*" + escaped + "\\b|\\b" + escaped + "\\s*\\*").test(code)) {
    inferredType = "ponteiro";
  }

  // 7) Variável de ciclo: for ( tipo palavra ; ou for ( ; palavra ;
  if (!inferredType) {
    if (new RegExp("for\\s*\\([^)]*\\b" + escaped + "\\b[^)]*\\)").test(code)) {
      inferredType = "variável de ciclo";
    }
  }

  // 8) IL: .locals ( tipo palavra )
  if (!inferredType && new RegExp("\\.locals\\s*\\([^)]*\\b" + escaped + "\\b", "i").test(code)) {
    inferredType = "local (IL)";
  }

  const blocks = getCBlocks(code);
  let functionsCount = 0;
  let maliciousCount = 0;
  for (const block of blocks) {
    const blockLines = lines.slice(block.start - 1, block.end).join("\n");
    if (new RegExp("\\b" + escaped + "\\b").test(blockLines)) {
      functionsCount++;
      const isMalicious = maliciousRanges?.some(
        (r) => block.start >= r.start && block.end <= r.end
      );
      if (isMalicious) maliciousCount++;
    }
  }

  return { mentions, inferredType, functionsCount, maliciousCount };
}

/** Agrupa o relatório em categorias tipo "Suspicious Imports: 3 ocorrências = 15/15 pontos". */
export function parseReportCategories(report: string): ReportCategory[] {
  const lines = report.split("\n");
  const categories: ReportCategory[] = [];
  const summaryRe = /:\s*\d+\s+ocorr/i; // procura "...: N ocorr..."
  const lineNumRe = /(?:linha|line)\s*(\d+)/i;

  let current: ReportCategory | null = null;

  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    if (summaryRe.test(trimmed)) {
      const id = `${trimmed}-${i + 1}`;
      current = {
        id,
        label: trimmed,
        summaryLineIndex: i + 1,
        lineNumbers: [],
      };
      categories.push(current);
      return;
    }

    if (current) {
      const m = lineNumRe.exec(line);
      if (m) {
        const n = parseInt(m[1], 10);
        if (!Number.isNaN(n)) current.lineNumbers.push(n);
      }
    }
  });

  return categories;
}

/** Extrai do relatório secções e itens como "flags" (marcadores) para navegação e teleporte no código */
export function parseReportFlags(report: string): ReportFlag[] {
  const lines = report.split("\n");
  const flags: ReportFlag[] = [];
  const lineNumRe = /(?:linha|line)\s*(\d+)/i;
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    const isHeading = trimmed.startsWith("##") || trimmed.startsWith("# ");
    const isBullet = trimmed.startsWith("- ") || trimmed.startsWith("• ");
    if (!isHeading && !isBullet) return;
    const label = trimmed.replace(/^#+\s*/, "").replace(/^[-•]\s*/, "").trim();
    if (!label) return;
    const lineMatch = lineNumRe.exec(line);
    const lineNum = lineMatch ? parseInt(lineMatch[1], 10) : undefined;
    flags.push({
      label: label.slice(0, 80) + (label.length > 80 ? "…" : ""),
      line: lineNum,
      reportLineIndex: i + 1,
    });
  });
  return flags;
}

/** Extrai os "capítulos" principais do relatório (RESUMO, SCORE DE RISCO, ANÁLISE ESTÁTICA, etc.) */
export function parseReportChapters(report: string): ReportChapter[] {
  const lines = report.split("\n");
  const chapters: ReportChapter[] = [];
  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    if (/^[=-]{5,}$/.test(trimmed)) return;
    const isAllCaps =
      /^[A-Z0-9ÁÀÂÃÉÈÊÍÓÔÕÚÇ ,./()-]+$/.test(trimmed) && trimmed.length <= 80;
    if (!isAllCaps) return;
    chapters.push({
      label: trimmed,
      line: i + 1,
    });
  });
  return chapters;
}

/** Um par antes/depois da deobfuscação (um "caso"). */
export type SnippetPair = { before: string; after: string; description?: string };

/**
 * Faz o parse do conteúdo de ficheiro de snippets (formato backend: "--- snippet N ---", metadata, depois código).
 * Devolve array de { description?, code }.
 */
export function parseSnippetFileSections(text: string): { description?: string; code: string }[] {
  if (!text?.trim()) return [];
  const sections = text.split(/\n--- snippet \d+ ---\n/).filter(Boolean);
  return sections.map((block) => {
    const firstDoubleNewline = block.indexOf("\n\n");
    const meta = firstDoubleNewline >= 0 ? block.slice(0, firstDoubleNewline) : "";
    const code = (firstDoubleNewline >= 0 ? block.slice(firstDoubleNewline + 2) : block).trim();
    const descMatch = meta.match(/description:\s*(.+)/);
    const description = descMatch ? descMatch[1].trim() : undefined;
    return { description, code };
  });
}

/** Junta listas de snippets obfuscados e deobfuscados em pares antes/depois (por índice). */
export function zipSnippetPairs(
  obfSections: { description?: string; code: string }[],
  deobSections: { description?: string; code: string }[]
): SnippetPair[] {
  const maxLen = Math.max(obfSections.length, deobSections.length);
  const pairs: SnippetPair[] = [];
  for (let i = 0; i < maxLen; i++) {
    const obf = obfSections[i];
    const deob = deobSections[i];
    pairs.push({
      before: obf?.code ?? "",
      after: deob?.code ?? "",
      description: obf?.description ?? deob?.description,
    });
  }
  return pairs.filter((p) => p.before.trim() || p.after.trim());
}

/** Extrai a secção "Indicadores de Ofuscação" do relatório para mostrar quando não há ficheiro de trechos. */
export function extractObfuscationIndicatorsFromReport(report: string): string | null {
  if (!report?.trim()) return null;
  const lines = report.split("\n");
  const out: string[] = [];
  let inSection = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (/Indicadores de [Oo]fuscação/i.test(trimmed)) {
      inSection = true;
      out.push("Indicadores de ofuscação (secção DEOBFUSCAÇÃO do relatório):");
      out.push("");
      continue;
    }
    if (inSection) {
      if (!trimmed) break;
      if (trimmed.startsWith("-") || trimmed.startsWith("  -")) {
        out.push(trimmed.replace(/^[\s-]+/, "  • "));
      } else if (/^[-=]{2,}$/.test(trimmed)) break;
      else out.push(trimmed);
    }
  }
  if (out.length <= 2) return null;
  return out.join("\n");
}
