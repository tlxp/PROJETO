// --- Módulo: equivalence.ts ---
// Equivalência de resultados e deteção de análise em curso.

import type { AnalysisResult, FlaggedFunction } from "./types";

// --- Equivalência e estado da análise ---
// *Comparação de resultados (polling) e deteção de análise estática em curso*

export function resolveFlaggedFunctionId(f: FlaggedFunction): string {
  return (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`;
}

export function flaggedFunctionsSignature(
  functions: FlaggedFunction[] | undefined | null
): string {
  if (!functions?.length) return "";
  return functions.map(resolveFlaggedFunctionId).join("\0");
}

export function areAnalysisResultsEquivalent(a: AnalysisResult, b: AnalysisResult): boolean {
  if (a === b) return true;
  return (
    a.report === b.report &&
    a.cCode === b.cCode &&
    a.ilCode === b.ilCode &&
    a.fileName === b.fileName &&
    a.riskScore === b.riskScore &&
    a.riskLevel === b.riskLevel &&
    a.dynamicSummary === b.dynamicSummary &&
    a.dynamicSimulated === b.dynamicSimulated &&
    a.vmReport === b.vmReport &&
    a.dynamicPending === b.dynamicPending &&
    a.staticPending === b.staticPending &&
    a.staticProgress === b.staticProgress &&
    a.obfuscatedSnippetsFile === b.obfuscatedSnippetsFile &&
    a.obfuscatedSnippetsDeobfuscatedFile === b.obfuscatedSnippetsDeobfuscatedFile &&
    a.obfuscationIndicatorCount === b.obfuscationIndicatorCount &&
    (a.flaggedIndicators ?? []).join("\0") === (b.flaggedIndicators ?? []).join("\0") &&
    flaggedFunctionsSignature(a.flaggedFunctions) === flaggedFunctionsSignature(b.flaggedFunctions)
  );
}

export function isStaticAnalysisInProgress(
  result: AnalysisResult | null,
  isAnalyzing: boolean
): boolean {
  if (!result) return isAnalyzing;
  if (result.staticPending) return true;
  if (!isAnalyzing) return false;
  const hasReport = !!(result.report && result.report.trim());
  const hasCCode = !!(result.cCode && result.cCode.trim());
  return !hasReport || !hasCCode;
}
