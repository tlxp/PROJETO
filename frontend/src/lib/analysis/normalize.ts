// --- Módulo: normalize.ts ---
// Normalização de payloads JSON da API para tipos internos.

import type { AnalysisResult, FlaggedFunction } from "./types";

// --- Normalização de payloads API ---
// *Conversão segura de JSON do backend para tipos internos*

export function asRecord(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
}

function filterStrings(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

function readLineNumber(rf: Record<string, unknown>, camel: string, snake: string): number {
  const v = rf[camel] ?? rf[snake];
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

function normalizeFlaggedFunctions(v: unknown): FlaggedFunction[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
    .map((f) => {
      const rf = asRecord(f) ?? {};
      return {
        name: typeof rf.name === "string" ? rf.name : "",
        id: typeof rf.id === "string" ? rf.id : undefined,
        startLine: readLineNumber(rf, "startLine", "start_line"),
        endLine: readLineNumber(rf, "endLine", "end_line"),
        indicators: filterStrings(rf.indicators),
        score: typeof rf.score === "number" ? rf.score : undefined,
        scoreRaw: typeof rf.scoreRaw === "number" ? rf.scoreRaw : undefined,
        severity: typeof rf.severity === "string" ? rf.severity : undefined,
        reasons: filterStrings(rf.reasons),
      };
    });
}

export function isFlaggedRangeInCode(totalLines: number, f: FlaggedFunction): boolean {
  return f.startLine > 0 && f.endLine > 0 && f.startLine <= totalLines;
}

export function clampFlaggedFunctionsToCode(
  cCode: string,
  flaggedFunctions: FlaggedFunction[] | undefined | null
): FlaggedFunction[] {
  if (!flaggedFunctions?.length || !cCode) return [];
  const totalLines = cCode.split("\n").length;
  if (totalLines <= 0) return [];
  return flaggedFunctions
    .filter((f) => isFlaggedRangeInCode(totalLines, f))
    .map((f) => ({
      ...f,
      endLine: Math.min(f.endLine, totalLines),
    }));
}

export function normalizeAnalysisResult(
  r: Record<string, unknown>,
  fallbackFileName?: string
): AnalysisResult {
  return {
    report: typeof r.report === "string" ? r.report : "",
    cCode: typeof r.cCode === "string" ? r.cCode : "",
    ilCode: typeof r.ilCode === "string" ? r.ilCode : "",
    fileName: typeof r.fileName === "string" ? r.fileName : (fallbackFileName ?? "output"),
    riskScore: typeof r.riskScore === "number" ? r.riskScore : 0,
    riskLevel: typeof r.riskLevel === "string" ? r.riskLevel : "",
    flaggedIndicators: filterStrings(r.flaggedIndicators),
    flaggedFunctions: normalizeFlaggedFunctions(r.flaggedFunctions),
    dynamicSummary: null,
    dynamicSimulated: false,
    vmReport: null,
    dynamicPending: false,
    staticPending: false,
    obfuscatedSnippetsFile:
      typeof r.obfuscatedSnippetsFile === "string" ? r.obfuscatedSnippetsFile : undefined,
    obfuscatedSnippetsDeobfuscatedFile:
      typeof r.obfuscatedSnippetsDeobfuscatedFile === "string"
        ? r.obfuscatedSnippetsDeobfuscatedFile
        : undefined,
    obfuscationIndicatorCount:
      typeof r.obfuscationIndicatorCount === "number" ? r.obfuscationIndicatorCount : undefined,
    staticProgress:
      typeof r.staticProgress === "number" && Number.isFinite(r.staticProgress)
        ? r.staticProgress
        : null,
  };
}
