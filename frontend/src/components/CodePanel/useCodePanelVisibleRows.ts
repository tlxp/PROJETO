// --- Módulo: useCodePanelVisibleRows.ts ---
// Construção de linhas visíveis (janela, ranges, limite).

import { useMemo } from "react";
import type { DisplayLineRange, Row } from "./types";

// --- Tipos ---
export type UseCodePanelVisibleRowsOptions = {
  lines: string[];
  totalLines: number;
  isWindowMode: boolean;
  windowStart: number | null;
  windowEnd: number | null;
  displayLineRanges?: DisplayLineRange[] | null;
  showAll: boolean;
  maxInitialLines: number;
};

// --- Hook ---
export function useCodePanelVisibleRows({
  lines,
  totalLines,
  isWindowMode,
  windowStart,
  windowEnd,
  displayLineRanges,
  showAll,
  maxInitialLines,
}: UseCodePanelVisibleRowsOptions) {
  const visibleRows = useMemo<Row[]>(() => {
    if (isWindowMode && windowStart != null && windowEnd != null && totalLines > 0) {
      const rows: Row[] = [];
      if (windowStart > 1) rows.push({ type: "gap", start: 1, end: windowStart - 1 });
      for (let n = windowStart; n <= windowEnd; n++) {
        const line = lines[n - 1];
        if (line !== undefined) rows.push({ type: "code", lineNumber: n, line });
      }
      if (windowEnd < totalLines) rows.push({ type: "gap", start: windowEnd + 1, end: totalLines });
      return rows;
    }

    if (displayLineRanges && displayLineRanges.length > 0) {
      const rows: Row[] = [];
      for (let r = 0; r < displayLineRanges.length; r++) {
        const { start, end } = displayLineRanges[r];
        for (let n = start; n <= end; n++) {
          const line = lines[n - 1];
          if (line !== undefined) rows.push({ type: "code", lineNumber: n, line });
        }
      }
      return rows;
    }

    const shouldLimit = !showAll && totalLines > maxInitialLines;
    const slice = shouldLimit ? lines.slice(0, maxInitialLines) : lines;
    return slice.map((line, i) => ({ type: "code", lineNumber: i + 1, line }));
  }, [
    displayLineRanges,
    isWindowMode,
    lines,
    maxInitialLines,
    showAll,
    totalLines,
    windowEnd,
    windowStart,
  ]);

  const shouldLimit =
    !isWindowMode && !displayLineRanges?.length && !showAll && totalLines > maxInitialLines;

  return { visibleRows, shouldLimit };
}
