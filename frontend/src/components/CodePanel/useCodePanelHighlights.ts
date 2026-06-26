// --- Módulo: useCodePanelHighlights.ts ---
// Destaques de funções suspeitas e lookup por linha.

import { useCallback, useMemo } from "react";
import type { FunctionHighlight } from "./types";

// --- Tipos ---
export type UseCodePanelHighlightsOptions = {
  functionHighlights?: FunctionHighlight[] | null;
};

// --- Hook ---
export function useCodePanelHighlights({ functionHighlights }: UseCodePanelHighlightsOptions) {
  const functionHighlightRanges = useMemo(() => {
    const ranges =
      (functionHighlights ?? [])
        .filter((f) => f && typeof f.startLine === "number" && typeof f.endLine === "number")
        .map((f) => ({
          start: Math.max(1, Math.floor(f.startLine)),
          end: Math.max(1, Math.floor(f.endLine)),
          f,
        }))
        .filter((r) => r.start <= r.end)
        .sort((a, b) => a.start - b.start || a.end - b.end) ?? [];
    return ranges;
  }, [functionHighlights]);

  const getFunctionForLine = useCallback(
    (lineNumber: number): FunctionHighlight | null => {
      if (!functionHighlightRanges.length) return null;
      for (let i = functionHighlightRanges.length - 1; i >= 0; i--) {
        const r = functionHighlightRanges[i];
        if (lineNumber < r.start) continue;
        if (lineNumber >= r.start && lineNumber <= r.end) return r.f;
        break;
      }
      for (let i = 0; i < functionHighlightRanges.length; i++) {
        const r = functionHighlightRanges[i];
        if (lineNumber < r.start) break;
        if (lineNumber >= r.start && lineNumber <= r.end) return r.f;
      }
      return null;
    },
    [functionHighlightRanges],
  );

  return { getFunctionForLine };
}
