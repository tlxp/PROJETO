// --- Módulo: vmReport.ts ---
// Formatação e parsing de relatórios comportamentais da VM.

import { getT } from "@/i18n";

// --- Relatório VM ---
// *Reparação de encoding, parsing de secções, scoring e formatação para display*

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

// *Repara encoding linha a linha — evita corromper UTF-8 já válido*
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

export function translateVmClassification(raw: string | null | undefined): string | null {
  if (!raw?.trim()) return null;
  const trimmed = raw.trim();
  const mapped = VM_CLASSIFICATION_PT[trimmed.toLowerCase()];
  return mapped ?? trimmed.toUpperCase();
}

export function isVmClassificationBenign(classification: string | null | undefined): boolean {
  if (!classification?.trim()) return false;
  const normalized = translateVmClassification(classification);
  return normalized === "BENIGNO";
}

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
  if (/^[+\-~]/.test(trimmed)) return true;
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
    if (/^[+\-~]/.test(t)) registry++;
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

export function getDisplayVmReport(report: string | null | undefined): string {
  return formatVmReportForDisplay(report ?? "");
}
