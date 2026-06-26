// --- Módulo: jobs.ts ---
// Construção de resultados a partir de jobs e publicação na API.

import { apiFetchJson } from "../api";
import { asRecord, normalizeAnalysisResult } from "./normalize";
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
  const dynamicSummary =
    dr && typeof dr.dynamicSummary === "string" ? dr.dynamicSummary : base.dynamicSummary ?? null;
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
    dynamicSummary,
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
    const dynamicSummary =
      typeof dr.dynamicSummary === "string" ? dr.dynamicSummary : "Análise dinâmica concluída.";
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
        dynamicSummary,
        vmReport,
        dynamicPending: false,
        staticPending: computeStaticPending("", jobStatus, analysisType),
      };
    }
    const behaviorStr = dr.dynamicReport != null ? JSON.stringify(dr.dynamicReport, null, 2) : "";
    return {
      report: `# Análise dinâmica\n\n${dynamicSummary}\n\n${behaviorStr}`,
      cCode: "",
      ilCode: "",
      fileName: fallbackFileName ?? "output",
      riskScore: 0,
      riskLevel: "",
      flaggedIndicators: [],
      dynamicSummary,
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
