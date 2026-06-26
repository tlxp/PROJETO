// --- Módulo: useCodePanelFold.ts ---
// Fold de blocos e collapsedFoldStarts.

import { useCallback, useEffect, useMemo, useState } from "react";
import { getFoldBlocks } from "./utils";
import type { Row } from "./types";

// --- Tipos ---
export type UseCodePanelFoldOptions = {
  lines: string[];
  language: string;
  visibleRows: Row[];
  scrollToLine?: number | null;
  onWordSelect?: (word: string) => void;
};

// --- Hook ---
export function useCodePanelFold({
  lines,
  language,
  visibleRows,
  scrollToLine,
  onWordSelect,
}: UseCodePanelFoldOptions) {
  const [collapsedFoldStarts, setCollapsedFoldStarts] = useState<Set<number>>(new Set());
  const [hoveredBlock, setHoveredBlock] = useState<{ start: number; end: number } | null>(null);

  const foldBlocks = useMemo(() => getFoldBlocks(lines), [lines]);
  const blockEndByStart = useMemo(
    () => new Map(foldBlocks.map((b) => [b.startLine, b.endLine])),
    [foldBlocks],
  );
  const blockStartByEnd = useMemo(
    () => new Map(foldBlocks.map((b) => [b.endLine, b.startLine])),
    [foldBlocks],
  );
  const isFoldableLanguage = language === "C" || language === "MSIL" || language === "c";

  const toggleFold = useCallback((startLine: number) => {
    setCollapsedFoldStarts((prev) => {
      const next = new Set(prev);
      if (next.has(startLine)) next.delete(startLine);
      else next.add(startLine);
      return next;
    });
  }, []);

  const handleCodeDoubleClick = useCallback(() => {
    if (!onWordSelect) return;
    requestAnimationFrame(() => {
      const sel = window.getSelection();
      const raw = (sel?.toString() ?? "").trim();
      const word = raw.includes(" ") ? (raw.split(/\s+/)[0] ?? raw) : raw;
      if (/^[a-zA-Z_]\w*$/.test(word) && word.length >= 2) {
        onWordSelect(word);
      }
    });
  }, [onWordSelect]);

  const foldedRows = useMemo<Row[]>(() => {
    if (!isFoldableLanguage || foldBlocks.length === 0) return visibleRows;
    const out: Row[] = [];
    for (const row of visibleRows) {
      if (row.type === "gap") {
        out.push(row);
        continue;
      }
      if (row.type === "code") {
        const L = row.lineNumber;
        const endLine = blockEndByStart.get(L);
        if (endLine != null && collapsedFoldStarts.has(L)) {
          out.push(row);
          out.push({ type: "foldPlaceholder", startLine: L, endLine });
          continue;
        }
        const isInsideCollapsed = foldBlocks.some(
          (b) => collapsedFoldStarts.has(b.startLine) && L > b.startLine && L <= b.endLine,
        );
        if (isInsideCollapsed) continue;
        out.push(row);
      }
    }
    return out;
  }, [
    visibleRows,
    isFoldableLanguage,
    foldBlocks,
    blockEndByStart,
    collapsedFoldStarts,
  ]);

  useEffect(() => {
    if (scrollToLine == null || scrollToLine < 1) return;
    const block = foldBlocks.find((b) => scrollToLine >= b.startLine && scrollToLine <= b.endLine);
    if (block && collapsedFoldStarts.has(block.startLine)) {
      setCollapsedFoldStarts((prev) => {
        const next = new Set(prev);
        next.delete(block.startLine);
        return next;
      });
    }
  }, [scrollToLine, foldBlocks, collapsedFoldStarts]);

  return {
    foldedRows,
    collapsedFoldStarts,
    foldBlocks,
    blockEndByStart,
    blockStartByEnd,
    isFoldableLanguage,
    toggleFold,
    hoveredBlock,
    setHoveredBlock,
    handleCodeDoubleClick,
  };
}
