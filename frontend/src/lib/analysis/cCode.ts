// --- Módulo: cCode.ts ---
// Blocos pseudo-C, ranges de display e estatísticas de identificadores.

import { escapeRegex, isValidIdentifier } from "../identifiers";
import { getBraceBlocksFromCode } from "../cBlockUtils";

// --- Pseudo-C ---
// *Blocos por chavetas, ranges de display e estatísticas de palavras*

// --- Blocos delimitados por chavetas ---
export function getCBlocks(code: string): { start: number; end: number }[] {
  return getBraceBlocksFromCode(code);
}

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
