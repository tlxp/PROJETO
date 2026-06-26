// --- Módulo: useCodePanelDownload.ts ---
// Ações de download do painel de código.

import { useCallback, useMemo, useState } from "react";
import type { DisplayLineRange, FunctionHighlight } from "./types";

// --- Tipos ---
export type UseCodePanelDownloadOptions = {
  code: string;
  lines: string[];
  downloadFileName?: string | null;
  displayLineRanges?: DisplayLineRange[] | null;
  functionHighlights?: FunctionHighlight[] | null;
};

// --- Hook ---
export function useCodePanelDownload({
  code,
  lines,
  downloadFileName,
  displayLineRanges,
  functionHighlights,
}: UseCodePanelDownloadOptions) {
  const [downloadDialogOpen, setDownloadDialogOpen] = useState(false);

  const hasFlaggedFunctions = (functionHighlights?.length ?? 0) > 0;
  const currentFlaggedRange =
    displayLineRanges && displayLineRanges.length > 0 ? displayLineRanges[0] : null;

  const buildDownloadName = useCallback(
    (variant: "full" | "flagged_current" | "flagged_all") => {
      const name = downloadFileName ?? "output.txt";
      const dot = name.lastIndexOf(".");
      const base = dot > 0 ? name.slice(0, dot) : name;
      const ext = dot > 0 ? name.slice(dot) : "";
      if (variant === "full") return name;
      if (variant === "flagged_current") return `${base}.flagged-current${ext || ".txt"}`;
      return `${base}.flagged-all${ext || ".txt"}`;
    },
    [downloadFileName],
  );

  const extractRangesText = useCallback(
    (ranges: { start: number; end: number }[]) => {
      const out: string[] = [];
      for (const r of ranges) {
        const start = Math.max(1, Math.floor(r.start));
        const end = Math.max(start, Math.floor(r.end));
        const chunk = lines.slice(start - 1, end).join("\n");
        if (chunk.trim().length) out.push(chunk);
      }
      return out.join("\n\n");
    },
    [lines],
  );

  const doDownload = useCallback((text: string, fileName: string) => {
    const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = fileName;
    a.click();
    URL.revokeObjectURL(a.href);
  }, []);

  const handleDownload = useCallback(() => {
    if (!downloadFileName) return;
    setDownloadDialogOpen(true);
  }, [downloadFileName]);

  const downloadFull = useCallback(() => {
    if (!downloadFileName) return;
    doDownload(code, buildDownloadName("full"));
    setDownloadDialogOpen(false);
  }, [buildDownloadName, code, doDownload, downloadFileName]);

  const downloadCurrentFlagged = useCallback(() => {
    if (!downloadFileName) return;
    if (!hasFlaggedFunctions || !currentFlaggedRange) return;
    const text = extractRangesText([currentFlaggedRange]);
    doDownload(text, buildDownloadName("flagged_current"));
    setDownloadDialogOpen(false);
  }, [
    buildDownloadName,
    currentFlaggedRange,
    doDownload,
    downloadFileName,
    extractRangesText,
    hasFlaggedFunctions,
  ]);

  const downloadAllFlagged = useCallback(() => {
    if (!downloadFileName) return;
    if (!hasFlaggedFunctions) return;
    const ranges = (functionHighlights ?? []).map((f) => ({ start: f.startLine, end: f.endLine }));
    const text = extractRangesText(ranges);
    doDownload(text, buildDownloadName("flagged_all"));
    setDownloadDialogOpen(false);
  }, [buildDownloadName, doDownload, downloadFileName, extractRangesText, functionHighlights, hasFlaggedFunctions]);

  return useMemo(
    () => ({
      downloadDialogOpen,
      setDownloadDialogOpen,
      hasFlaggedFunctions,
      currentFlaggedRange,
      handleDownload,
      downloadFull,
      downloadCurrentFlagged,
      downloadAllFlagged,
    }),
    [
      currentFlaggedRange,
      downloadAllFlagged,
      downloadCurrentFlagged,
      downloadDialogOpen,
      downloadFull,
      handleDownload,
      hasFlaggedFunctions,
    ],
  );
}
