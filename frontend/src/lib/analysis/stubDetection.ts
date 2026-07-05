// --- Módulo: stubDetection.ts ---
// Deteção e formatação de relatórios dinâmicos simulados (driver stub).

import { getT } from "@/i18n";
import type { AnalysisResult } from "./types";

export const STUB_DOWNLOAD_PREFIX =
  "[MODO: SIMULADO — driver stub — amostra não executada]";

export type StubReportMeta = {
  isStub: boolean;
  note?: string;
  summary?: string;
  fileName?: string;
};

export function isVmDriverStub(vmDriver: string | null | undefined): boolean {
  const name = (vmDriver ?? "").trim().toLowerCase();
  return name === "stub" || name === "safe" || name === "disabled";
}

function readStubFromObject(o: Record<string, unknown>): StubReportMeta | null {
  const status = typeof o.status === "string" ? o.status : "";
  const driver = typeof o.driver === "string" ? o.driver : "";
  const sandboxEngine = typeof o.sandboxEngine === "string" ? o.sandboxEngine : "";
  const isStub = status === "stub" || driver === "stub" || sandboxEngine === "stub";
  if (!isStub) return null;

  const sample = o.sample as Record<string, unknown> | undefined;
  return {
    isStub: true,
    note: typeof o.note === "string" ? o.note : undefined,
    fileName: sample && typeof sample.fileName === "string" ? sample.fileName : undefined,
  };
}

export function parseDynamicReportStub(raw: string | null | undefined): StubReportMeta {
  if (!raw?.trim()) return { isStub: false };
  const trimmed = raw.trim();
  if (!trimmed.startsWith("{")) return { isStub: false };
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (!parsed || typeof parsed !== "object") return { isStub: false };
    return readStubFromObject(parsed as Record<string, unknown>) ?? { isStub: false };
  } catch {
    return { isStub: false };
  }
}

export function isDynamicReportObjectStub(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  return readStubFromObject(value as Record<string, unknown>)?.isStub === true;
}

export function buildStubVmReportDisplay(opts?: {
  note?: string | null;
  summary?: string | null;
  fileName?: string | null;
}): string {
  const lines = [
    STUB_DOWNLOAD_PREFIX,
    "",
    "===============================================================================",
    getT("stubReportTitle"),
    "===============================================================================",
    "",
    getT("stubReportHeadline"),
    "",
  ];

  if (opts?.fileName?.trim()) {
    lines.push(`${getT("stubReportSample")}: ${opts.fileName.trim()}`, "");
  }
  if (opts?.summary?.trim()) {
    lines.push(opts.summary.trim(), "");
  }

  lines.push(
    getT("stubReportEvidence"),
    `  - ${getT("reportProcesses")}: ${getT("stubReportNa")}`,
    `  - ${getT("reportNetwork")}: ${getT("stubReportNa")}`,
    `  - ${getT("reportRegistry")}: ${getT("stubReportNa")}`,
    `  - ${getT("reportFiles")}: ${getT("stubReportNa")}`,
    "",
    getT("stubReportNoScore"),
    ""
  );

  const note = opts?.note?.trim();
  if (note) {
    lines.push(getT("stubReportNote"), note, "");
  }

  lines.push(getT("stubReportConfigure"), "");
  return lines.join("\n");
}

export function resolveDynamicSimulated(
  dynamicReport: unknown,
  vmReportRaw: string,
  dynamicSummary?: string | null
): boolean {
  if (isDynamicReportObjectStub(dynamicReport)) return true;
  if (parseDynamicReportStub(vmReportRaw).isStub) return true;
  const summary = (dynamicSummary ?? "").toLowerCase();
  return summary.includes("(stub)") || summary.includes("simulad");
}

export function isResultDynamicallySimulated(result: AnalysisResult | null | undefined): boolean {
  if (!result) return false;
  if (result.dynamicSimulated) return true;
  return resolveDynamicSimulated(null, result.vmReport ?? "", result.dynamicSummary);
}
