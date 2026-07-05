// --- Módulo: jobs.ts ---
// Construção de resultados a partir de jobs e publicação na API.

import { apiFetchJson } from "../api";
import { asRecord, normalizeAnalysisResult } from "./normalize";
import { resolveDynamicSimulated } from "./stubDetection";
import type { AnalysisResult } from "./types";

// --- Jobs e publicação na API ---
// *Construção de AnalysisResult a partir de jobs e upload de resultados estáticos*

function extractVmReportFromDynamic(dr: Record<string, unknown> | null): string {
  if (!dr) return "";
  if (typeof dr.dynamicReportText === "string" && dr.dynamicReportText.trim()) {
    return dr.dynamicReportText;
  }
  if (typeof dr.report === "string" && dr.report.trim() && !dr.cCode) {
    return dr.report;
  }
  if (dr.dynamicReport != null && typeof dr.dynamicReport === "string") {
    return dr.dynamicReport;
  }
  if (dr.dynamicReport != null && typeof dr.dynamicReport === "object") {
    return JSON.stringify(dr.dynamicReport, null, 2);
  }
  return "";
}

function computeStaticPending(
  report: string,
  jobStatus?: string,
  analysisType?: string
): boolean {
  if (report.trim()) return false;
  const status = (jobStatus ?? "").toLowerCase();
  if (status !== "running" && status !== "queued") return false;
  const type = (analysisType ?? "").toLowerCase();
  return type === "static" || type === "both";
}

function resolveDynamicSummary(
  dr: Record<string, unknown> | null,
  vmReport: string,
  fallback?: string | null
): string | null {
  if (dr && typeof dr.dynamicSummary === "string" && dr.dynamicSummary.trim()) {
    return dr.dynamicSummary;
  }
  if (fallback?.trim()) return fallback;
  if (resolveDynamicSimulated(dr?.dynamicReport, vmReport)) {
    return "Análise dinâmica simulada (stub). A amostra não foi executada.";
  }
  return "Análise dinâmica concluída.";
}

function buildDynamicMeta(
  dr: Record<string, unknown> | null,
  vmReport: string,
  fallbackSummary?: string | null
): Pick<AnalysisResult, "dynamicSummary" | "dynamicSimulated"> {
  const dynamicSummary = resolveDynamicSummary(dr, vmReport, fallbackSummary);
  return {
    dynamicSummary,
    dynamicSimulated: resolveDynamicSimulated(dr?.dynamicReport, vmReport, dynamicSummary),
  };
}

function computeDynamicPending(
  vmReport: string,
  jobStatus?: string,
  analysisType?: string,
  hasDynamicResult?: boolean
): boolean {
  if (vmReport.trim()) return false;
  const status = (jobStatus ?? "").toLowerCase();
  if (status === "running" || status === "queued" || status === "pending") return true;
  // *VM registada (both + dynamicResult) mas relatório ainda por chegar — ex. estática
  // marcou o job como completed antes do fim da análise na VM*
  const type = (analysisType ?? "").toLowerCase();
  return type === "both" && !!hasDynamicResult;
}

function mergeDynamicFields(
  base: AnalysisResult,
  dynamicResult: unknown,
  jobStatus?: string,
  analysisType?: string
): AnalysisResult {
  const dr = asRecord(dynamicResult);
  const vmReport = extractVmReportFromDynamic(dr);
  const dynamicMeta = buildDynamicMeta(dr, vmReport, base.dynamicSummary ?? null);
  const dynamicPending = computeDynamicPending(
    vmReport,
    jobStatus,
    analysisType,
    !!dr
  );
  const staticPending =
    computeStaticPending(base.report, jobStatus, analysisType) || !!base.staticPending;

  return {
    ...base,
    vmReport: vmReport || null,
    dynamicSummary: dynamicMeta.dynamicSummary,
    dynamicSimulated: dynamicMeta.dynamicSimulated,
    dynamicPending,
    staticPending,
    staticProgress: base.staticProgress ?? null,
  };
}

export function buildAnalysisResultFromJob(
  job: unknown,
  fallbackFileName?: string
): AnalysisResult | null {
  const fj = asRecord(job);
  if (!fj) return null;

  const jobStatus = typeof fj.status === "string" ? fj.status : undefined;
  const analysisType = typeof fj.analysisType === "string" ? fj.analysisType : undefined;

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

  const sr = asRecord(staticResult);
  if (sr) {
    return mergeDynamicFields(
      normalizeAnalysisResult(sr, fallbackFileName),
      dynamicResult,
      jobStatus,
      analysisType
    );
  }

  const dr = asRecord(dynamicResult);
  if (dr) {
    const vmReport = extractVmReportFromDynamic(dr);
    const dynamicMeta = buildDynamicMeta(dr, vmReport);
    if (vmReport) {
      return {
        report: "",
        cCode: "",
        ilCode: "",
        fileName:
          typeof dr.fileName === "string"
            ? dr.fileName
            : (fallbackFileName ?? "output"),
        riskScore: 0,
        riskLevel: "",
        flaggedIndicators: [],
        dynamicSummary: dynamicMeta.dynamicSummary,
        dynamicSimulated: dynamicMeta.dynamicSimulated,
        vmReport,
        dynamicPending: false,
        staticPending: computeStaticPending("", jobStatus, analysisType),
      };
    }
    const behaviorStr = dr.dynamicReport != null ? JSON.stringify(dr.dynamicReport, null, 2) : "";
    return {
      report: `# Análise dinâmica\n\n${dynamicMeta.dynamicSummary}\n\n${behaviorStr}`,
      cCode: "",
      ilCode: "",
      fileName: fallbackFileName ?? "output",
      riskScore: 0,
      riskLevel: "",
      flaggedIndicators: [],
      dynamicSummary: dynamicMeta.dynamicSummary,
      dynamicSimulated: dynamicMeta.dynamicSimulated,
      vmReport: behaviorStr || null,
      dynamicPending: (jobStatus ?? "").toLowerCase() === "running",
      staticPending: computeStaticPending("", jobStatus, analysisType),
    };
  }

  if (computeStaticPending("", jobStatus, analysisType)) {
    return {
      report: "",
      cCode: "",
      ilCode: "",
      fileName: fallbackFileName ?? "output",
      riskScore: 0,
      riskLevel: "",
      flaggedIndicators: [],
      dynamicSummary: null,
      vmReport: null,
      dynamicPending: false,
      staticPending: true,
    };
  }

  // Fallback: alguns payloads antigos podem trazer campos diretos no root.
  if (typeof fj.report === "string" || typeof fj.cCode === "string" || typeof fj.ilCode === "string") {
    return normalizeAnalysisResult(fj, fallbackFileName);
  }

  return null;
}

export async function publishStaticAnalysisResult(
  result: AnalysisResult,
  signal?: AbortSignal | null
): Promise<string> {
  const data = await apiFetchJson<{ jobId?: string }>("/api/analysis/upload_static", {
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
    signal,
  });
  if (!data.jobId) {
    throw new Error("Resposta inesperada ao publicar resultado estático (jobId em falta).");
  }
  return data.jobId;
}
