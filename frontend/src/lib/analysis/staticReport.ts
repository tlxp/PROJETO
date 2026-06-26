// --- Módulo: staticReport.ts ---
// Parsing do relatório estático (categorias, capítulos, snippets).

import type { ReportCategory, ReportChapter } from "./types";

// --- Parsing estático do relatório ---
// *Categorias, capítulos, resumo e indicadores de ofuscação*

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

export type SnippetPair = { before: string; after: string; description?: string };

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
