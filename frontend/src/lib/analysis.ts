/**
 * Lógica de domínio da análise (tipos, normalização de resultados e parsing do relatório).
 * Partilhada entre a página principal, hooks de streaming/polling e o explorador de xrefs.
 */

import { getT } from "@/i18n";
import { apiFetchJson } from "./api";
import { escapeRegex, isValidIdentifier } from "./identifiers";

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
  /** Indicadores (funções/strings) que deram flag para highlight no pseudo-C (vindo do backend). */
  flaggedIndicators?: string[];
  /** Resumo opcional de análise dinâmica (quando existir). */
  dynamicSummary?: string | null;
  /** Relatório textual completo da análise na VM (Caminho B — Hyper-V). */
  vmReport?: string | null;
  /** True quando a análise dinâmica está em curso mas o relatório ainda não chegou. */
  dynamicPending?: boolean;
  /** True quando a análise estática está em curso mas o relatório ainda não chegou. */
  staticPending?: boolean;
  /** Progresso Ghidra (0–100) publicado pelo WPF durante análise estática. */
  staticProgress?: number | null;
  /** Funções suspeitas com ranges exatos no pseudo-C (vindo do backend). */
  flaggedFunctions?: FlaggedFunction[];
  /** Caminho do ficheiro com trechos obfuscados extraídos (quando existir). */
  obfuscatedSnippetsFile?: string;
  /** Caminho do ficheiro com trechos deobfuscados (quando existir). */
  obfuscatedSnippetsDeobfuscatedFile?: string;
  /** Número de indicadores de ofuscação (corresponde à categoria Obfuscation do relatório). */
  obfuscationIndicatorCount?: number;
};

export type AnalysisMode = "static" | "dynamic" | "both";

export type ExpandedPanel = "c" | "il" | "report" | "report-static" | "report-vm" | null;

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

/** Indica se o range de uma função suspeita cabe no pseudo-C efectivamente carregado. */
export function isFlaggedRangeInCode(totalLines: number, f: FlaggedFunction): boolean {
  return f.startLine > 0 && f.endLine > 0 && f.startLine <= totalLines;
}

/**
 * Mantém apenas funções cujos ranges existem no texto C actual (ex.: após truncagem no backend).
 */
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

/**
 * Normalização única de um payload "tipo resultado estático" (streaming NDJSON,
 * `staticResult` de um job ou campos diretos no root) para `AnalysisResult`.
 */
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

/** Repara texto UTF-8 lido como Latin-1 (ex.: "alteraÃ§Ãµes" → "alterações"). */
function repairUtf8Mojibake(text: string): string {
  if (!/[ÃÂ]/.test(text)) return text;
  try {
    const latin1 = new Uint8Array([...text].map((ch) => ch.charCodeAt(0) & 0xff));
    const repaired = new TextDecoder("utf-8", { fatal: false }).decode(latin1);
    if (/[ãõçáéíóúàêô]|ção|ções/i.test(repaired)) return repaired;
  } catch {
    /* manter original */
  }
  return text;
}

function countPortugueseAccents(text: string): number {
  return (text.match(/[áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]/g) || []).length;
}

/** Repara encoding linha a linha (evita corromper UTF-8 válido no resto do relatório). */
function repairVmReportText(text: string): string {
  if (!text) return "";
  return text
    .split(/\r?\n/)
    .map((line) => {
      if (!/[ÃÂ\uFFFD]|ï¿½/.test(line)) return line;
      const mojibake = repairUtf8Mojibake(line);
      if (mojibake !== line) return mojibake;
      try {
        const latin1 = new Uint8Array([...line].map((ch) => ch.charCodeAt(0) & 0xff));
        const attempt = new TextDecoder("utf-8", { fatal: false }).decode(latin1);
        if (countPortugueseAccents(attempt) > countPortugueseAccents(line)) return attempt;
      } catch {
        /* manter linha */
      }
      return line;
    })
    .join("\n");
}

function canonicalVmSectionTitle(title: string): string {
  const t = repairVmReportText(title).trim();
  const upper = t.toUpperCase();
  if (/^ALTERA.{0,4}ES EM FICHEIROS/.test(upper)) return "ALTERAÇÕES EM FICHEIROS";
  if (/^ALTERA.{0,4}ES NO REGIST/.test(upper)) return "ALTERAÇÕES NO REGISTO";
  if (/^EXECU.{0,4}O DA AMOSTRA/.test(upper)) return "EXECUÇÃO DA AMOSTRA";
  if (/^BASELINE/.test(upper)) {
    return upper.replace(/EXECU.{0,4}O/, "EXECUÇÃO");
  }
  if (/^AVALIA.{0,4}O DE RISCO/.test(upper) || upper === "SCORING") {
    return "AVALIAÇÃO DE RISCO (SCORING)";
  }
  if (/^ARTEFATOS DE EXECU/.test(upper)) {
    return "ARTEFATOS DE EXECUÇÃO (PREFETCH/AMCACHE/SHIMCACHE/SRUM)";
  }
  if (/^SERVI.{0,4}OS \(NOVOS EM EXECU/.test(upper)) {
    return "SERVIÇOS (NOVOS EM EXECUÇÃO)";
  }
  if (/TENTATIVAS DE REDE \/ CONEX/.test(upper)) {
    return "TENTATIVAS DE REDE / CONEXÕES";
  }
  if (upper === "ALTERAÇÕES NO REGISTRY") return "ALTERAÇÕES NO REGISTO";
  return upper;
}

export type VmScoringSummary = {
  score: number | null;
  scoreRaw: number | null;
  scoreMax: number | null;
  classification: string | null;
  knownValidationSample: boolean;
};

const VM_CLASSIFICATION_PT: Record<string, string> = {
  benign: "BENIGNO",
  suspicious: "SUSPEITO",
  malicious: "MALICIOSO",
  not_executed: "NÃO EXECUTADO",
  execution_timeout: "TIMEOUT DE EXECUÇÃO",
  failed_to_start: "FALHA AO INICIAR",
  execution_failed: "EXECUÇÃO INVÁLIDA",
  benigno: "BENIGNO",
  suspeito: "SUSPEITO",
  malicioso: "MALICIOSO",
  "não executado": "NÃO EXECUTADO",
  "nao executado": "NÃO EXECUTADO",
  "timeout de execução": "TIMEOUT DE EXECUÇÃO",
  "timeout de execucao": "TIMEOUT DE EXECUÇÃO",
  "falha ao iniciar": "FALHA AO INICIAR",
  "execução inválida": "EXECUÇÃO INVÁLIDA",
  "execucao invalida": "EXECUÇÃO INVÁLIDA",
  "execução falhou": "EXECUÇÃO INVÁLIDA",
};

/** Normaliza classificações VM (inglês legado ou PT) para rótulos em português. */
export function translateVmClassification(raw: string | null | undefined): string | null {
  if (!raw?.trim()) return null;
  const trimmed = raw.trim();
  const mapped = VM_CLASSIFICATION_PT[trimmed.toLowerCase()];
  return mapped ?? trimmed.toUpperCase();
}

/** True quando a classificação VM indica comportamento benigno/inofensivo. */
export function isVmClassificationBenign(classification: string | null | undefined): boolean {
  if (!classification?.trim()) return false;
  const normalized = translateVmClassification(classification);
  return normalized === "BENIGNO";
}

function localizeVmSectionTitle(title: string): string {
  return canonicalVmSectionTitle(title);
}

/** Extrai score/classificação do relatório textual da VM. */
export function parseVmScoringFromReport(report: string | null | undefined): VmScoringSummary | null {
  if (!report?.trim()) return null;
  const lines = repairVmReportText(report ?? "").split(/\r?\n/);
  let score: number | null = null;
  let scoreRaw: number | null = null;
  let scoreMax: number | null = null;
  let classification: string | null = null;
  let knownValidationSample = false;

  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const m100 =
      line.match(/Score(?:\s+total)?\s*\(0-100\):\s*(\d+)\s*\/\s*100/i) ??
      line.match(/^Score:\s*(\d+)\s*\/\s*100/i);
    if (m100) score = Number.parseInt(m100[1], 10);
    const mRaw =
      line.match(/Score(?:\s+total)?\s*\(bruto\):\s*(\d+)\s*\/\s*(\d+)/i) ??
      line.match(/^Score bruto:\s*(\d+)\s*\/\s*(\d+)/i);
    if (mRaw) {
      scoreRaw = Number.parseInt(mRaw[1], 10);
      scoreMax = Number.parseInt(mRaw[2], 10);
    }
    const mClass =
      line.match(/^Classifica.{0,6}:\s*(.+)$/i) ?? line.match(/^N[ií]vel:\s*(.+)$/i);
    if (mClass) classification = translateVmClassification(mClass[1].trim());
    if (/BenignVmTest|valida\w+\s+conhecida/i.test(line)) knownValidationSample = true;
  }

  if (score == null && classification == null && scoreRaw == null) return null;
  return { score, scoreRaw, scoreMax, classification, knownValidationSample };
}

/** Compara scores estático vs VM quando ambos existem. */
export function compareAnalysisScores(
  staticScore: number,
  staticLevel: string,
  vm: VmScoringSummary | null
): {
  hasBoth: boolean;
  diverges: boolean;
  summary: string | null;
} {
  if (!vm || (vm.score == null && !vm.classification)) {
    return { hasBoth: false, diverges: false, summary: null };
  }
  const staticHigh = staticScore >= 40 || /alto|cr[ií]tico|m[eé]dio/i.test(staticLevel);
  const vmLow = isVmClassificationBenign(vm.classification);
  const diverges = staticHigh && vmLow;
  let summary: string | null = null;
  if (diverges) {
    summary = vm.knownValidationSample
      ? "Estática alta; VM benigna (amostra de validação)."
      : "Scores divergem: ficheiro vs execução.";
  }
  return { hasBoth: true, diverges, summary };
}

const VM_REPORT_SEP_EQ = "=".repeat(80);
const VM_REPORT_SEP_MAJOR = "-".repeat(80);
const VM_REPORT_SEP_RESUMO = "-".repeat(40);

function vmReportTitle() {
  return getT("reportTitleVm");
}

type VmReportMeta = {
  dataHora?: string;
  amostra?: string;
  hash?: string;
  inicio?: string;
  fim?: string;
};

type VmScoringBlock = {
  score?: string;
  scoreRaw?: string;
  nivel?: string;
  tempoExec?: string;
  notes: string[];
};

type VmReportSection = {
  title: string;
  lines: string[];
};

function normalizeVmBulletLine(trimmed: string): string {
  const body = trimmed.replace(/^[-•]\s*/, "").replace(/^\s{2}-\s*/, "");
  return `  - ${body}`;
}

function shouldVmLineBeBullet(trimmed: string): boolean {
  if (/^[-•]\s/.test(trimmed) || /^\s{2}-\s/.test(trimmed)) return true;
  if (/^[\+\-~]/.test(trimmed)) return true;
  return /^(Foi (?:criado|modificado|removido|observado|detetado)|Application Error:|WER:|SideBySide:)/i.test(
    trimmed
  );
}

function isVmReportFooterLine(line: string): boolean {
  const t = line.trim();
  return /^(REPORT_END;?\s*|FIM\s+DO\s+RELAT)/i.test(t);
}

function normalizeVmNoteText(trimmed: string): string {
  const m = trimmed.match(/^Nota:\s*(.+)$/i);
  return repairVmReportText(m ? m[1].trim() : trimmed);
}

function formatVmContentLine(trimmed: string): string {
  if (isVmReportFooterLine(trimmed)) return "";
  if (/^Nota:/i.test(trimmed)) return normalizeVmNoteText(trimmed);
  if (shouldVmLineBeBullet(trimmed)) return normalizeVmBulletLine(trimmed);
  const mScore100 = trimmed.match(/^Score(?:\s+total)?\s*\(0-100\):\s*(.+)$/i);
  if (mScore100) return `Score: ${mScore100[1].trim()}`;
  const mScoreRaw = trimmed.match(/^Score(?:\s+total)?\s*\(bruto\):\s*(.+)$/i);
  if (mScoreRaw) return `Score bruto: ${mScoreRaw[1].trim()}`;
  if (/^Score:\s/i.test(trimmed) && !/^Score bruto:/i.test(trimmed)) return trimmed;
  if (/^Score bruto:/i.test(trimmed)) return trimmed;
  const mClass = trimmed.match(/^Classifica.{0,6}:\s*(.+)$/i);
  if (mClass) {
    const nivel = translateVmClassification(mClass[1].trim());
    return nivel ? `Nível: ${nivel}` : trimmed;
  }
  const mNivel = trimmed.match(/^N[ií]vel:\s*(.+)$/i);
  if (mNivel) {
    const nivel = translateVmClassification(mNivel[1].trim());
    return nivel ? `Nível: ${nivel}` : trimmed;
  }
  if (/^Tempo de execu/i.test(trimmed)) return repairVmReportText(trimmed);
  return repairVmReportText(trimmed);
}

function isVmScoringSectionTitle(title: string): boolean {
  const canonical = canonicalVmSectionTitle(title);
  return (
    canonical.includes("AVALIAÇÃO DE RISCO") ||
    canonical === "SCORE DE RISCO" ||
    /\bSCORING\b/.test(canonical)
  );
}

function isStructuralVmSectionTitle(title: string): boolean {
  const u = canonicalVmSectionTitle(title);
  return u === "RESUMO" || u === "INFORMAÇÕES DO FICHEIRO" || u === "SCORE DE RISCO";
}

function extractVmBehaviorCounts(lines: string[]): {
  files: number;
  processes: number;
  registry: number;
  network: string;
} {
  let files = 0;
  let processes = 0;
  let registry = 0;
  let network = "N/D";
  for (const line of lines) {
    const t = line.trim();
    if (/^Foi (?:criado|modificado|removido) o ficheiro:/i.test(t)) files++;
    if (/^Foi (?:criado|observado) o processo:/i.test(t)) processes++;
    if (/^[\+\-~]/.test(t)) registry++;
    if (/Foram observadas (?:diferenças nas conexões|alterações nas conexões)/i.test(t)) {
      network = "alterada";
    }
    if (/Não foram detetadas alterações nas conexões/i.test(t)) network = "sem alterações";
  }
  return { files, processes, registry, network };
}

function extractVmScoringBlock(
  lines: string[],
  opts: { notes?: boolean } = { notes: true }
): VmScoringBlock {
  const block: VmScoringBlock = { notes: [] };
  for (const raw of lines) {
    const t = raw.trim();
    if (!t) continue;
    if (opts.notes && /^Nota:/i.test(t)) {
      const note = normalizeVmNoteText(t);
      if (!block.notes.includes(note)) block.notes.push(note);
      continue;
    }
    if (opts.notes && /BenignVmTest|valida\w+\s+conhecida/i.test(t)) {
      const note = normalizeVmNoteText(t);
      if (!block.notes.includes(note)) block.notes.push(note);
      continue;
    }
    const formatted = formatVmContentLine(t);
    if (/^Score:\s/i.test(formatted) && !/^Score bruto:/i.test(formatted)) {
      block.score = formatted;
    } else if (/^Score bruto:/i.test(formatted)) {
      block.scoreRaw = formatted;
    } else if (/^Nível:/i.test(formatted)) {
      block.nivel = formatted;
    } else if (/^Tempo de execu/i.test(formatted)) {
      block.tempoExec = formatted;
    }
  }
  return block;
}

function mergeVmScoringBlocks(primary: VmScoringBlock, fallback: VmScoringBlock): VmScoringBlock {
  return {
    score: primary.score ?? fallback.score,
    scoreRaw: primary.scoreRaw ?? fallback.scoreRaw,
    nivel: primary.nivel ?? fallback.nivel,
    tempoExec: primary.tempoExec ?? fallback.tempoExec,
    notes: primary.notes.length > 0 ? primary.notes : fallback.notes,
  };
}

function appendVmMajorSection(out: string[], title: string): void {
  out.push(VM_REPORT_SEP_MAJOR, title, VM_REPORT_SEP_MAJOR);
}

function captureVmMetaField(meta: VmReportMeta, line: string): void {
  const mData = line.match(/^Data\/Hora:\s*(.+)$/i);
  if (mData) {
    meta.dataHora = mData[1].trim();
    return;
  }
  const mAmostra = line.match(/^Amostra:\s*(.+)$/i);
  if (mAmostra) {
    meta.amostra = mAmostra[1].trim();
    return;
  }
  const mHash = line.match(/^Hash SHA256:\s*(.+)$/i);
  if (mHash) {
    meta.hash = mHash[1].trim();
    return;
  }
  const mInicio = line.match(/^In[ií]cio(?: da an[aá]lise)?:\s*(.+)$/i);
  if (mInicio) {
    meta.inicio = mInicio[1].trim();
    return;
  }
  const mFim = line.match(/^Fim(?: da an[aá]lise)?:\s*(.+)$/i);
  if (mFim) {
    meta.fim = mFim[1].trim();
  }
}

function parseVmReportSource(repaired: string): {
  meta: VmReportMeta;
  sections: VmReportSection[];
  scoring: VmScoringBlock;
  allBodyLines: string[];
} {
  const text = repairVmReportText(repaired);
  const meta: VmReportMeta = {};
  const sections: VmReportSection[] = [];
  const scoringLines: string[] = [];
  const allBodyLines: string[] = [];
  let current: VmReportSection | null = null;
  let headerEquals = 0;
  let headerClosed = false;
  let inScoringSection = false;
  let expectMajorTitle = false;

  const startSection = (title: string) => {
    if (current) sections.push(current);
    const canonical = canonicalVmSectionTitle(title);
    if (isVmScoringSectionTitle(canonical)) {
      inScoringSection = true;
      current = null;
      return;
    }
    inScoringSection = false;
    current = { title: canonical, lines: [] };
  };

  const pushLine = (line: string) => {
    allBodyLines.push(line);
    if (inScoringSection) scoringLines.push(line);
    else if (current) current.lines.push(line);
  };

  for (const raw of text.split(/\r?\n/)) {
    const t = raw.trim();
    if (!t || isVmReportFooterLine(t)) continue;

    const secMatch = t.match(/^---\s*(.+?)\s*---\s*$/);
    if (secMatch) {
      headerClosed = true;
      startSection(secMatch[1]);
      continue;
    }

    if (/^={5,}$/.test(t)) {
      if (!headerClosed) {
        headerEquals++;
        if (headerEquals >= 2) headerClosed = true;
      }
      continue;
    }

    if (/^-{5,}$/.test(t) && headerClosed) {
      expectMajorTitle = true;
      continue;
    }

    if (expectMajorTitle) {
      expectMajorTitle = false;
      if (isStructuralVmSectionTitle(t)) {
        if (current) {
          sections.push(current);
          current = null;
        }
        inScoringSection = false;
        continue;
      }
      headerClosed = true;
      startSection(t);
      continue;
    }

    if (!headerClosed) {
      if (/^RELATÓRIO DE ANÁLISE/i.test(t)) continue;
      captureVmMetaField(meta, t);
      continue;
    }

    if (
      !current &&
      !inScoringSection &&
      !/^RESUMO$/i.test(t) &&
      !/^-{5,}$/.test(t) &&
      /^[A-Z0-9ÁÀÂÃÉÈÊÍÓÔÕÚÇ ,./()\-—]+$/.test(t) &&
      t.length <= 90 &&
      /[A-ZÁÀÂÃÉÈÊÍÓÔÕÚÇ]{4,}/.test(t)
    ) {
      startSection(t);
      continue;
    }

    pushLine(t);
  }

  if (current) sections.push(current);

  const scoringFromSection = extractVmScoringBlock(scoringLines, { notes: true });
  const scoringFromBody = extractVmScoringBlock(allBodyLines, { notes: false });
  const scoring = mergeVmScoringBlocks(scoringFromSection, scoringFromBody);

  return { meta, sections, scoring, allBodyLines };
}

function buildVmResumoLines(
  allBodyLines: string[],
  override?: { files: number; processes: number; registry: number; network: string }
): string[] {
  const counts = override ?? extractVmBehaviorCounts(allBodyLines);
  return [
    getT("reportResumo"),
    VM_REPORT_SEP_RESUMO,
    `  ${getT("reportFiles")}: ${counts.files}  |  ${getT("reportProcesses")}: ${counts.processes}  |  ${getT("reportRegistry")}: ${counts.registry}  |  ${getT("reportNetwork")}: ${counts.network}`,
    "",
  ];
}

function buildVmFileInfoLines(meta: VmReportMeta): string[] {
  const lines: string[] = [];
  appendVmMajorSection(lines, getT("reportFileInfo"));
  const content: string[] = [];
  if (meta.amostra) {
    const name = meta.amostra.replace(/^.*[\\/]/, "");
    content.push(`Nome: ${name}`);
    content.push(`Caminho: ${meta.amostra}`);
  }
  if (meta.hash) content.push(`SHA256: ${meta.hash}`);
  if (meta.inicio) content.push(`Início da análise: ${meta.inicio}`);
  if (meta.fim) content.push(`Fim da análise: ${meta.fim}`);
  if (content.length === 0) content.push(getT("reportNd"));
  lines.push(...content, "");
  return lines;
}

function buildVmScoreLines(scoring: VmScoringBlock): string[] {
  const lines: string[] = [];
  appendVmMajorSection(lines, getT("reportRiskScore"));
  if (scoring.score) lines.push(scoring.score);
  if (scoring.scoreRaw) lines.push(scoring.scoreRaw);
  if (scoring.nivel) lines.push(scoring.nivel);
  if (scoring.tempoExec) lines.push(scoring.tempoExec);
  const uniqueNotes = [...new Set(scoring.notes)];
  lines.push(...uniqueNotes);
  if (!scoring.score && !scoring.scoreRaw && !scoring.nivel && scoring.notes.length === 0) {
    lines.push(getT("reportNd"));
  }
  lines.push("", getT("reportRiskExplain"), getT("reportRiskInconclusive"), "");
  return lines;
}

function buildStaticStyleVmReport(parts: {
  meta: VmReportMeta;
  scoring: VmScoringBlock;
  sections: VmReportSection[];
  allBodyLines: string[];
  resumoOverride?: { files: number; processes: number; registry: number; network: string };
}): string {
  const out: string[] = [VM_REPORT_SEP_EQ, vmReportTitle(), VM_REPORT_SEP_EQ];
  if (parts.meta.dataHora) out.push(`Data/Hora: ${parts.meta.dataHora}`);
  out.push("");
  out.push(...buildVmResumoLines(parts.allBodyLines, parts.resumoOverride));
  out.push(...buildVmFileInfoLines(parts.meta));
  out.push(...buildVmScoreLines(parts.scoring));

  for (const section of parts.sections) {
    if (isVmScoringSectionTitle(section.title)) continue;
    appendVmMajorSection(out, canonicalVmSectionTitle(section.title));
    const seen = new Set<string>();
    for (const raw of section.lines) {
      const t = repairVmReportText(raw).trim();
      if (!t || isVmReportFooterLine(t)) continue;
      if (/^Score(?:\s+total)?\s*\(/i.test(t) || /^Classifica/i.test(t)) continue;
      if (/^Nota:/i.test(t) || /BenignVmTest|valida\w+\s+conhecida/i.test(t)) continue;
      if (/^\d+\s+altera.{0,12}es foram classificadas como ru[ií]do do SO/i.test(t)) continue;
      const formatted = formatVmContentLine(t);
      if (!formatted || seen.has(formatted)) continue;
      seen.add(formatted);
      out.push(formatted);
    }
    out.push("");
  }

  return out.join("\n").trimEnd() + "\n";
}

function formatVmReportFromJson(value: unknown): string {
  if (!value || typeof value !== "object") return String(value ?? "");
  const o = value as Record<string, unknown>;
  const scoringObj = (o.scoring as Record<string, unknown> | undefined) ?? {};
  const summary = (o.summary as Record<string, unknown> | undefined) ?? {};

  const meta: VmReportMeta = {
    amostra: typeof o.sample_path === "string" ? o.sample_path : undefined,
    hash: typeof o.sample_sha256 === "string" ? o.sample_sha256 : undefined,
    inicio: o.analysis_start ? String(o.analysis_start) : undefined,
    fim: o.analysis_end ? String(o.analysis_end) : undefined,
  };

  const classification =
    typeof scoringObj.classification === "string"
      ? translateVmClassification(scoringObj.classification)
      : null;
  const scoreNorm = typeof scoringObj.score === "number" ? scoringObj.score : null;
  const scoreRaw = typeof scoringObj.scoreRaw === "number" ? scoringObj.scoreRaw : null;
  const scoreMax = typeof scoringObj.scoreMax === "number" ? scoringObj.scoreMax : null;

  const scoring: VmScoringBlock = {
    notes: [],
    score: scoreNorm != null ? `Score: ${scoreNorm}/100` : undefined,
    scoreRaw:
      scoreRaw != null && scoreMax != null ? `Score bruto: ${scoreRaw}/${scoreMax}` : undefined,
    nivel: classification ? `Nível: ${classification}` : undefined,
    tempoExec:
      typeof scoringObj.runtimeSeconds === "number"
        ? `Tempo de execução: ${scoringObj.runtimeSeconds}s`
        : undefined,
  };

  const pseudoBody: string[] = [];
  const fileCount = Number(summary.file_changes_count ?? 0);
  const procCount = Number(summary.new_processes_count ?? 0);
  if (fileCount > 0) pseudoBody.push(`Foi criado o ficheiro: (${fileCount} alterações)`);
  if (procCount > 0) pseudoBody.push(`Foi criado o processo: (${procCount} novos)`);

  return buildStaticStyleVmReport({
    meta,
    scoring,
    sections: [],
    allBodyLines: pseudoBody,
    resumoOverride: {
      files: fileCount,
      processes: procCount,
      registry: Number(summary.registry_changes_count ?? 0),
      network: summary.network_changed ? "alterada" : "sem alterações",
    },
  });
}

function isAlreadyFormattedVmReport(text: string): boolean {
  return (
    /RELATÓRIO DE ANÁLISE COMPORTAMENTAL/i.test(text) &&
    /^SCORE DE RISCO$/m.test(text) &&
    /^RESUMO$/m.test(text)
  );
}

function normalizeFormattedVmReport(text: string): string {
  let lines = repairVmReportText(text).split(/\r?\n/);

  let lastDup = -1;
  let hasScore = false;
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    if (/^SCORE DE RISCO$/i.test(t)) hasScore = true;
    if (hasScore && isVmScoringSectionTitle(t) && !/^SCORE DE RISCO$/i.test(t)) {
      lastDup = i;
    }
  }
  if (lastDup >= 0) {
    let start = lastDup;
    while (start > 0 && /^[-=]{5,}$/.test(lines[start - 1].trim())) start--;
    lines = lines.slice(0, start);
  }

  const out: string[] = [];
  for (const raw of lines) {
    const t = repairVmReportText(raw).trim();
    if (!t || isVmReportFooterLine(t)) continue;
    if (/^={5,}$/.test(t)) {
      out.push(VM_REPORT_SEP_EQ);
      continue;
    }
    if (/^-{5,}$/.test(t)) {
      out.push(VM_REPORT_SEP_MAJOR);
      continue;
    }
    if (/^-{40}$/.test(t)) {
      out.push(VM_REPORT_SEP_RESUMO);
      continue;
    }
    if (/^RELATÓRIO DE ANÁLISE/i.test(t)) {
      out.push(vmReportTitle());
      continue;
    }
    if (isVmScoringSectionTitle(t)) continue;

    const canonical = canonicalVmSectionTitle(t);
    const looksLikeSectionTitle =
      t === t.toUpperCase() &&
      t.length <= 90 &&
      /^[A-ZÁÀÂÃÉÈÊÍÓÔÕÚÇ0-9 ,./()\-—]+$/.test(t) &&
      !/^Score:/i.test(t) &&
      !/^Nível:/i.test(t) &&
      !/^Nome:/i.test(t) &&
      !/^SHA256:/i.test(t) &&
      !/^Caminho:/i.test(t) &&
      !/^Data\/Hora:/i.test(t);

    if (looksLikeSectionTitle) {
      out.push(canonical);
      continue;
    }

    const formatted = formatVmContentLine(t);
    if (formatted) out.push(formatted);
  }

  return out.join("\n").trimEnd() + "\n";
}

/**
 * Normaliza o relatório textual da VM para o mesmo estilo visual do relatório estático:
 * cabeçalho, RESUMO, INFORMAÇÕES DO FICHEIRO, SCORE DE RISCO e secções com separadores.
 */
export function formatVmReportForDisplay(raw: string): string {
  if (!raw?.trim()) return "";
  const repaired = repairVmReportText(raw);
  const trimmed = repaired.trim();
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      return formatVmReportFromJson(JSON.parse(trimmed));
    } catch {
      /* continuar como texto */
    }
  }

  if (isAlreadyFormattedVmReport(repaired)) {
    return normalizeFormattedVmReport(repaired);
  }

  const parsed = parseVmReportSource(repaired);
  return buildStaticStyleVmReport(parsed);
}

/** Texto do relatório VM pronto para apresentação no frontend. */
export function getDisplayVmReport(report: string | null | undefined): string {
  return formatVmReportForDisplay(report ?? "");
}

/** Extrai o texto do relatório dinâmico a partir do payload `dynamicResult`. */
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
  const status = (jobStatus ?? "").toLowerCase();
  const dynamicPending =
    !vmReport &&
    (status === "running" || status === "queued" || status === "pending");
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

/** Constrói um AnalysisResult a partir do payload de um job da API /api/analysis. */
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

/** Publica um resultado estático (obtido por streaming) no backend e devolve o jobId. */
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

/** ID estável de uma função suspeita (para seleção e comparação). */
export function resolveFlaggedFunctionId(f: FlaggedFunction): string {
  return (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`;
}

/** Assinatura compacta da lista de funções suspeitas (ignora referências de array). */
export function flaggedFunctionsSignature(
  functions: FlaggedFunction[] | undefined | null
): string {
  if (!functions?.length) return "";
  return functions.map(resolveFlaggedFunctionId).join("\0");
}

/** Compara dois resultados de análise ignorando identidade de objeto (útil no polling). */
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

/** Indica se a análise estática ainda não concluiu (streaming ou job em polling). */
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
export function mergeRanges(
  ranges: { start: number; end: number }[]
): { start: number; end: number }[] {
  if (ranges.length === 0) return [];
  const sorted = [...ranges].sort((a, b) => a.start - b.start);
  const out: { start: number; end: number }[] = [{ ...sorted[0] }];
  for (let i = 1; i < sorted.length; i++) {
    const cur = sorted[i];
    const last = out[out.length - 1];
    if (cur.start <= last.end + 1) {
      last.end = Math.max(last.end, cur.end);
    } else {
      out.push({ ...cur });
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
    .map((f) => {
      const a = Math.max(1, f.startLine);
      const b = Math.max(1, f.endLine);
      return { start: Math.min(a, b), end: Math.max(a, b) };
    })
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

export function getWordStats(
  code: string,
  word: string,
  maliciousRanges: { start: number; end: number }[] | undefined
): WordStats {
  // Valida o identificador antes de construir RegExp dinâmicas (além do escape).
  if (!word || word.length < 2 || !isValidIdentifier(word)) {
    return { mentions: 0, inferredType: null, functionsCount: 0, maliciousCount: 0 };
  }
  const escaped = escapeRegex(word);
  const re = new RegExp("\\b" + escaped + "\\b", "g");
  const mentions = (code.match(re) || []).length;

  const lines = code.split("\n");
  let inferredType: string | null = null;

  // 1) Declaração C: tipo + palavra (int x, void foo, ...)
  const cTypeRe = new RegExp(
    "\\b(int|void|char|long|short|float|double|bool|unsigned|size_t|uint\\w*|struct\\s+\\w+)\\s+" +
      escaped +
      "\\b"
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
      "\\b(string|var|bool|int|long|float|double|object|byte|sbyte|ushort|uint|ulong|decimal)\\s+" +
        escaped +
        "\\b"
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
      "[,(]\\s*(?:const\\s+)?(?:int|void|char|long|short|float|double|bool|unsigned|string|var)\\s+" +
        escaped +
        "\\s*[),]",
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

/** Linhas da secção RESUMO do relatório (se existir). */
export function parseReportResumoLines(report: string): string[] | null {
  if (!report) return null;
  const lines = report.split("\n");
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
