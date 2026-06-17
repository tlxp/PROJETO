import React, { useRef, useEffect, useMemo, useState, useCallback, useLayoutEffect } from "react";
import { motion } from "framer-motion";
import { Maximize2, Download, ChevronRight, ChevronDown } from "lucide-react";
import type {
  FunctionHighlight,
  Row,
  CodePanelProps,
} from "./CodePanel/types";
import { getFoldBlocks } from "./CodePanel/utils";
import { HighlightedLine } from "./CodePanel/HighlightedLine";
import GeminiAssistDialog from "./CodePanel/GeminiAssistDialog";
import GeminiIcon from "@/components/GeminiIcon";
import { buildCodeExcerpt } from "@/lib/gemini";

const CodePanel: React.FC<CodePanelProps> = ({
  title,
  language,
  code,
  icon,
  scrollToLine,
  onExpand,
  compactHeader,
  embedded = false,
  maxInitialLines = 1200,
  displayLineRanges,
  downloadFileName,
  windowFocusLine,
  windowContextLines = 1000,
  windowChunkLines = 400,
  windowMaxLines = 2500,
  permanentHighlightRanges,
  functionHighlights,
  onViewportLineChange,
  flaggedIndicators,
  selectedWord,
  onWordSelect,
  showDisplayRangesNotice = true,
  hideLimitNotice = false,
  hideWindowNotice = false,
  onWindowRangeChange,
  disableScroll = false,
  geminiAssist = false,
  geminiAllowMock = false,
}) => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showAll, setShowAll] = useState(false);
  const [downloadDialogOpen, setDownloadDialogOpen] = useState(false);
  const [geminiDialogOpen, setGeminiDialogOpen] = useState(false);
  const [windowStart, setWindowStart] = useState<number | null>(null);
  const [windowEnd, setWindowEnd] = useState<number | null>(null);
  const [collapsedFoldStarts, setCollapsedFoldStarts] = useState<Set<number>>(new Set());
  const [hoveredBlock, setHoveredBlock] = useState<{ start: number; end: number } | null>(null);
  const rowHeightRef = useRef<number | null>(null);
  const pendingScrollAdjustPxRef = useRef<number>(0);
  const lastShiftAtRef = useRef<number>(0);
  const lastViewportNotifyAtRef = useRef<number>(0);
  const lastViewportLineRef = useRef<number | null>(null);
  const lastScrollTopRef = useRef<number>(0);
  const lastWheelShiftAtRef = useRef<number>(0);
  const wheelRemainderPxRef = useRef<number>(0);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);

  const VIRTUALIZE_THRESHOLD = 150;
  const VIRTUAL_OVERSCAN = 20;
  const DEFAULT_ROW_HEIGHT = 18;

  const lines = useMemo(() => code.split("\n"), [code]);
  const totalLines = lines.length;

  const hasFlaggedFunctions = (functionHighlights?.length ?? 0) > 0;
  const currentFlaggedRange =
    displayLineRanges && displayLineRanges.length > 0
      ? displayLineRanges[0]
      : null;

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
    [downloadFileName]
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
    [lines]
  );

  const foldBlocks = useMemo(() => getFoldBlocks(lines), [lines]);
  const blockEndByStart = useMemo(
    () => new Map(foldBlocks.map((b) => [b.startLine, b.endLine])),
    [foldBlocks]
  );
  const blockStartByEnd = useMemo(
    () => new Map(foldBlocks.map((b) => [b.endLine, b.startLine])),
    [foldBlocks]
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

  const isWindowMode = windowFocusLine != null && windowFocusLine >= 1;
  const windowSize = Math.max(1, windowContextLines * 2 + 1);
  // No modo janela, mantemos sempre uma janela fixa de ±N linhas e deslizamos com scroll.

  const expandWindow = useCallback(
    (dir: "down" | "up", chunkOverride?: number) => {
      if (!isWindowMode || windowStart == null || windowEnd == null) return;
      if (totalLines <= windowSize) return;

      const now = Date.now();
      // Responder melhor a scroll rápido sem entrar em loop.
      if (now - lastShiftAtRef.current < 35) return;

      const curSize = windowEnd - windowStart + 1;
      // No modo janela, o "passo" deve ser configurável (ex.: 1 linha por tick).
      const baseChunk = Math.max(1, Math.floor(windowChunkLines));
      const chunk = Math.max(baseChunk, Math.min(400, Math.floor(chunkOverride ?? baseChunk)));
      const rowH = rowHeightRef.current ?? 18;

      if (dir === "down" && windowEnd < totalLines) {
        const newEnd = Math.min(totalLines, windowEnd + chunk);
        const newStart = Math.max(1, newEnd - curSize + 1);
        if (newStart !== windowStart || newEnd !== windowEnd) {
          const deltaStart = newStart - windowStart; // >0 remove linhas de cima
          pendingScrollAdjustPxRef.current += -deltaStart * rowH;
          lastShiftAtRef.current = now;
          setWindowStart(newStart);
          setWindowEnd(newEnd);
        }
      }

      if (dir === "up" && windowStart > 1) {
        const newStart = Math.max(1, windowStart - chunk);
        const newEnd = Math.min(totalLines, newStart + curSize - 1);
        if (newStart !== windowStart || newEnd !== windowEnd) {
          const deltaStart = newStart - windowStart; // <0 adiciona linhas em cima
          pendingScrollAdjustPxRef.current += -deltaStart * rowH;
          lastShiftAtRef.current = now;
          setWindowStart(newStart);
          setWindowEnd(newEnd);
        }
      }
    },
    [
      isWindowMode,
      totalLines,
      windowChunkLines,
      windowEnd,
      windowSize,
      windowStart,
    ]
  );

  const ensureRowHeight = useCallback((): number => {
    if (rowHeightRef.current != null && rowHeightRef.current > 0) return rowHeightRef.current;
    const el = scrollRef.current;
    if (!el) return 18;
    const tr = el.querySelector<HTMLTableRowElement>("tr[data-line]");
    if (!tr) return 18;
    const h = tr.getBoundingClientRect().height;
    if (h > 0) rowHeightRef.current = h;
    return rowHeightRef.current ?? 18;
  }, []);

  useEffect(() => {
    if (!isWindowMode) {
      setWindowStart(null);
      setWindowEnd(null);
      return;
    }
    const focus = Math.min(Math.max(1, windowFocusLine!), totalLines || 1);
    let start = Math.max(1, focus - windowContextLines);
    let end = Math.min(totalLines, focus + windowContextLines);
    if (end - start + 1 < windowSize) {
      if (start === 1) end = Math.min(totalLines, start + windowSize - 1);
      else if (end === totalLines) start = Math.max(1, end - windowSize + 1);
    }
    setWindowStart(start);
    setWindowEnd(end);
    setShowAll(false);
  }, [isWindowMode, windowFocusLine, totalLines, windowContextLines, windowSize]);

  useEffect(() => {
    if (!isWindowMode || !onWindowRangeChange) return;
    if (windowStart == null || windowEnd == null) return;
    onWindowRangeChange({ start: windowStart, end: windowEnd, totalLines });
  }, [isWindowMode, onWindowRangeChange, totalLines, windowEnd, windowStart]);

  /** Linhas a mostrar: modo janela (leve), ou ranges (funções com flag), ou tudo (com limite). */
  const visibleRows = useMemo<Row[]>(() => {
    // 1) Modo janela (±N linhas à volta do foco)
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

    // 2) Mostrar apenas ranges (ex.: funções com flag)
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

    // 3) Normal (tudo) com limite opcional
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
          (b) => collapsedFoldStarts.has(b.startLine) && L > b.startLine && L <= b.endLine
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

  const shouldLimit = !isWindowMode && !displayLineRanges?.length && !showAll && totalLines > maxInitialLines;

  const shouldVirtualize =
    !isWindowMode && !displayLineRanges?.length && foldedRows.length > VIRTUALIZE_THRESHOLD;

  const virtualSlice = useMemo(() => {
    if (!shouldVirtualize) {
      return { rows: foldedRows, topPad: 0, bottomPad: 0, startIdx: 0 };
    }
    const rowH = rowHeightRef.current ?? DEFAULT_ROW_HEIGHT;
    const start = Math.max(0, Math.floor(scrollTop / rowH) - VIRTUAL_OVERSCAN);
    const visible = Math.ceil(Math.max(viewportHeight, rowH) / rowH) + 2 * VIRTUAL_OVERSCAN;
    const end = Math.min(foldedRows.length, start + visible);
    return {
      rows: foldedRows.slice(start, end),
      topPad: start * rowH,
      bottomPad: Math.max(0, foldedRows.length - end) * rowH,
      startIdx: start,
    };
  }, [DEFAULT_ROW_HEIGHT, foldedRows, scrollTop, shouldVirtualize, viewportHeight]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const update = () => setViewportHeight(el.clientHeight);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

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
      // Como está ordenado por start, fazemos uma busca linear curta a partir do fim provável.
      // (normalmente há poucas funções com flag).
      for (let i = functionHighlightRanges.length - 1; i >= 0; i--) {
        const r = functionHighlightRanges[i];
        if (lineNumber < r.start) continue;
        if (lineNumber >= r.start && lineNumber <= r.end) return r.f;
        break;
      }
      // fallback
      for (let i = 0; i < functionHighlightRanges.length; i++) {
        const r = functionHighlightRanges[i];
        if (lineNumber < r.start) break;
        if (lineNumber >= r.start && lineNumber <= r.end) return r.f;
      }
      return null;
    },
    [functionHighlightRanges]
  );

  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const prevTop = lastScrollTopRef.current;
    const curTop = el.scrollTop;
    lastScrollTopRef.current = curTop;
    setScrollTop(curTop);
    const delta = curTop - prevTop;

    // Notificar linha aproximada no viewport (throttle) — útil para sincronizar lista lateral
    if (onViewportLineChange && rowHeightRef.current) {
      const now = Date.now();
      if (now - lastViewportNotifyAtRef.current > 120) {
        const rowH = rowHeightRef.current ?? 18;
        const approxIdx = Math.max(0, Math.floor((el.scrollTop + el.clientHeight * 0.35) / rowH));
        let pickedLine: number | null = null;
        let seen = 0;
        for (let i = 0; i < foldedRows.length; i++) {
          const r = foldedRows[i];
          if (r.type !== "code") continue;
          if (seen === approxIdx) {
            pickedLine = r.lineNumber;
            break;
          }
          seen++;
        }
        if (pickedLine == null) {
          const last = [...foldedRows].reverse().find((r) => r.type === "code") as
            | { type: "code"; lineNumber: number; line: string }
            | undefined;
          pickedLine = last?.lineNumber ?? null;
        }
        if (pickedLine != null && pickedLine !== lastViewportLineRef.current) {
          lastViewportLineRef.current = pickedLine;
          lastViewportNotifyAtRef.current = now;
          onViewportLineChange(pickedLine);
        }
      }
    }

    if (!isWindowMode || windowStart == null || windowEnd == null) return;
    if (totalLines <= windowSize) return;

    const thresholdPx = 260;
    const nearTop = el.scrollTop < thresholdPx;
    const nearBottom = el.scrollHeight - (el.scrollTop + el.clientHeight) < thresholdPx;
    // Evita loops que "carregam tudo": só expande quando o utilizador realmente moveu o scroll.
    const rowH = ensureRowHeight();
    const speedLines = Math.max(1, Math.min(200, Math.round(Math.abs(delta) / Math.max(1, rowH))));
    if (delta > 0 && nearBottom) expandWindow("down", speedLines);
    else if (delta < 0 && nearTop) expandWindow("up", speedLines);
  }, [
    foldedRows,
    isWindowMode,
    expandWindow,
    onViewportLineChange,
    totalLines,
    windowEnd,
    windowMaxLines,
    windowSize,
    windowStart,
  ]);

  const shiftWindowByWheel = useCallback(
    (direction: "up" | "down", linesToShift: number) => {
      if (!isWindowMode || windowStart == null || windowEnd == null) return;
      if (totalLines <= windowSize) return;
      const now = Date.now();
      // Wheel dispara muito rápido; queremos um "tick" previsível.
      if (now - lastWheelShiftAtRef.current < 16) return;
      lastWheelShiftAtRef.current = now;

      const chunk = Math.max(1, Math.floor(linesToShift));
      const maxKeep = Math.max(windowSize, windowMaxLines);
      const rowH = ensureRowHeight();

      if (direction === "down" && windowEnd < totalLines) {
        const newEnd = Math.min(totalLines, windowEnd + chunk);
        let newStart = windowStart;
        const expandedSize = newEnd - newStart + 1;
        if (expandedSize > maxKeep) newStart = Math.max(1, newEnd - maxKeep + 1);
        if (newStart !== windowStart || newEnd !== windowEnd) {
          const deltaStart = newStart - windowStart;
          if (deltaStart !== 0) pendingScrollAdjustPxRef.current += -deltaStart * rowH;
          setWindowStart(newStart);
          setWindowEnd(newEnd);
        }
      } else if (direction === "up" && windowStart > 1) {
        const newStart = Math.max(1, windowStart - chunk);
        let newEnd = windowEnd;
        const expandedSize = newEnd - newStart + 1;
        if (expandedSize > maxKeep) newEnd = Math.min(totalLines, newStart + maxKeep - 1);
        if (newStart !== windowStart || newEnd !== windowEnd) {
          const deltaStart = newStart - windowStart;
          if (deltaStart !== 0) pendingScrollAdjustPxRef.current += -deltaStart * rowH;
          setWindowStart(newStart);
          setWindowEnd(newEnd);
        }
      }
    },
    [ensureRowHeight, isWindowMode, totalLines, windowChunkLines, windowEnd, windowMaxLines, windowSize, windowStart]
  );

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const adj = pendingScrollAdjustPxRef.current;
    if (adj !== 0) {
      el.scrollTop += adj;
      pendingScrollAdjustPxRef.current = 0;
    }
  }, [windowStart, windowEnd]);

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

  useEffect(() => {
    if (scrollToLine == null || scrollToLine < 1) return;
    const container = scrollRef.current;
    if (!container) return;
    const lineEl = container.querySelector<HTMLElement>(`[data-line="${scrollToLine}"]`);
    if (!lineEl) return;
    const containerRect = container.getBoundingClientRect();
    const lineRect = lineEl.getBoundingClientRect();
    const offset = lineRect.top - containerRect.top + container.scrollTop;
    const target = offset - container.clientHeight / 2 + lineEl.clientHeight / 2;
    container.scrollTo({ top: Math.max(0, target), behavior: "smooth" });
  }, [scrollToLine, foldedRows]);

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

  const geminiCodeExcerpt = useMemo(
    () =>
      buildCodeExcerpt(lines, {
        displayLineRanges,
        windowStart: isWindowMode ? windowStart : null,
        windowEnd: isWindowMode ? windowEnd : null,
        maxInitialLines,
        showAll,
      }),
    [
      displayLineRanges,
      isWindowMode,
      lines,
      maxInitialLines,
      showAll,
      windowEnd,
      windowStart,
    ],
  );

  const downloadAllFlagged = useCallback(() => {
    if (!downloadFileName) return;
    if (!hasFlaggedFunctions) return;
    const ranges = (functionHighlights ?? []).map((f) => ({ start: f.startLine, end: f.endLine }));
    const text = extractRangesText(ranges);
    doDownload(text, buildDownloadName("flagged_all"));
    setDownloadDialogOpen(false);
  }, [buildDownloadName, doDownload, downloadFileName, extractRangesText, functionHighlights, hasFlaggedFunctions]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className={`flex flex-1 min-h-0 flex-col overflow-hidden bg-card ${embedded ? "h-full" : ""} ${
        embedded ? "" : "rounded-lg border border-border"
      }`}
    >
      {/* Header */}
      <div className="flex items-center gap-2 border-b border-border bg-secondary/50 px-4 py-2.5">
        <div className="flex gap-1.5">
          <span className="h-3 w-3 rounded-full bg-destructive/60" />
          <span className="h-3 w-3 rounded-full bg-code-string/60" />
          <span className="h-3 w-3 rounded-full bg-primary/60" />
        </div>
        <div className="ml-2 flex items-center gap-2">
          {icon}
          <span className="font-mono text-xs font-medium text-muted-foreground">{title}</span>
        </div>
        <span className="ml-auto flex items-center gap-2">
          <span className="rounded bg-muted px-2 py-0.5 font-mono text-[10px] text-muted-foreground">
            {language}
          </span>
          {downloadFileName && (
            <button
              type="button"
              onClick={handleDownload}
              className="rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
              title="Descarregar ficheiro"
              aria-label="Descarregar"
            >
              <Download className="h-3.5 w-3.5" />
            </button>
          )}
          {geminiAssist && (
            <button
              type="button"
              onClick={() => setGeminiDialogOpen(true)}
              className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
              title="Perguntar ao Gemini sobre o código visível"
              aria-label="Assistente Gemini"
            >
              <GeminiIcon className="h-4 w-4" />
            </button>
          )}
          {onExpand && (
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                onExpand();
              }}
              className="rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
              title="Expandir para ecrã inteiro"
              aria-label="Expandir"
            >
              <Maximize2 className="h-3.5 w-3.5" />
            </button>
          )}
        </span>
      </div>

      {geminiAssist && (
        <GeminiAssistDialog
          open={geminiDialogOpen}
          onClose={() => setGeminiDialogOpen(false)}
          codeExcerpt={geminiCodeExcerpt}
          allowMock={geminiAllowMock}
        />
      )}

      {downloadDialogOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-label="Opções de download"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) setDownloadDialogOpen(false);
          }}
        >
          <div className="w-full max-w-md rounded-lg border border-border bg-card shadow-lg">
            <div className="border-b border-border px-4 py-3">
              <div className="font-mono text-xs font-semibold text-muted-foreground">Descarregar</div>
              <div className="mt-1 text-sm text-foreground">O que quer descarregar?</div>
            </div>
            <div className="space-y-2 px-4 py-3">
              <button
                type="button"
                onClick={downloadFull}
                className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-left text-[12px] text-foreground hover:bg-secondary/70 transition-colors"
              >
                Código todo
              </button>
              <button
                type="button"
                onClick={downloadCurrentFlagged}
                disabled={!hasFlaggedFunctions || !currentFlaggedRange}
                className={`w-full rounded-md border px-3 py-2 text-left text-[12px] transition-colors ${
                  !hasFlaggedFunctions || !currentFlaggedRange
                    ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                    : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
                }`}
                title={
                  !hasFlaggedFunctions
                    ? "Sem funções flagged"
                    : !currentFlaggedRange
                      ? "Nenhuma função flagged ativa"
                      : "Descarregar apenas a função flagged atual"
                }
              >
                Função flagged atual
              </button>
              <button
                type="button"
                onClick={downloadAllFlagged}
                disabled={!hasFlaggedFunctions}
                className={`w-full rounded-md border px-3 py-2 text-left text-[12px] transition-colors ${
                  !hasFlaggedFunctions
                    ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                    : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
                }`}
                title={!hasFlaggedFunctions ? "Sem funções flagged" : "Descarregar todas as funções flagged"}
              >
                Todas as funções flagged
              </button>
            </div>
            <div className="flex items-center justify-end gap-2 border-t border-border px-4 py-3">
              <button
                type="button"
                onClick={() => setDownloadDialogOpen(false)}
                className="rounded-md border border-border bg-card px-3 py-1.5 text-[12px] text-muted-foreground hover:bg-secondary/50 hover:text-foreground transition-colors"
              >
                Cancelar
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Code area */}
      <div
        ref={scrollRef}
        onScroll={disableScroll ? undefined : handleScroll}
        onWheel={
          disableScroll
            ? undefined
            : (e) => {
                // Em modo janela, pode não existir overflow suficiente para disparar "scroll".
                // O wheel deve ainda assim permitir carregar mais contexto progressivamente.
                if (!isWindowMode) return;

                const rowH = ensureRowHeight();

                // DOWN: acompanhar velocidade (deltaY -> N linhas, com acumulador).
                if (e.deltaY > 0) {
                  const px = e.deltaY + wheelRemainderPxRef.current;
                  const denom = Math.max(8, rowH);
                  const lines = Math.trunc(Math.abs(px) / denom);
                  wheelRemainderPxRef.current = px - Math.sign(px) * lines * denom;
                  if (lines <= 0) return;
                  shiftWindowByWheel("down", lines);
                  return;
                }

                // UP: 1 por tick, sem acumular velocidade.
                if (e.deltaY < 0) {
                  wheelRemainderPxRef.current = 0;
                  shiftWindowByWheel("up", 1);
                }
              }
        }
        className={`flex-1 min-h-0 h-full ${disableScroll ? "overflow-hidden" : "overflow-auto"} code-block p-0 ${
          compactHeader ? "min-h-0" : ""
        }`}
      >
        <table className="w-full border-collapse">
          <tbody>
            {virtualSlice.topPad > 0 ? (
              <tr aria-hidden="true">
                <td
                  colSpan={language === "report" ? 1 : 3}
                  style={{ height: virtualSlice.topPad, padding: 0, border: 0 }}
                />
              </tr>
            ) : null}
            {virtualSlice.rows.map((row, idx) => {
              const rowIdx = virtualSlice.startIdx + idx;
              if (row.type === "gap") {
                return (
                  <tr key={`gap-${rowIdx}`} className="bg-muted/30">
                    <td className="w-5 min-w-[20px] border-r border-border/20 p-0" />
                    <td className="select-none border-r border-border/30 px-3 py-1 text-right text-[11px] text-muted-foreground/50 w-10">
                      …
                    </td>
                    <td className="px-4 py-1 text-[11px] text-muted-foreground italic">
                      linhas {row.start}–{row.end} omitidas
                    </td>
                  </tr>
                );
              }
              if (row.type === "foldPlaceholder") {
                const count = row.endLine - row.startLine;
                return (
                  <tr key={`fold-${row.startLine}-${row.endLine}-${rowIdx}`} className="bg-muted/20">
                    <td className="w-5 min-w-[20px] border-r border-border/20 p-0 align-middle" />
                    <td className="select-none border-r border-border/30 px-2 py-0.5 text-right text-[10px] text-muted-foreground/60 w-10" />
                    <td className="px-4 py-0.5 text-[11px] text-muted-foreground italic">
                      … {count} linha{count !== 1 ? "s" : ""} recolhida{count !== 1 ? "s" : ""}
                    </td>
                  </tr>
                );
              }
              const { lineNumber, line } = row;

              // Layout especial para relatório: sem números de linha nem coluna de fold,
              // visual mais próximo de documento em vez de editor de código.
              if (language === "report") {
                const setRowHeightRef = (el: HTMLTableRowElement | null) => {
                  if (!el || rowHeightRef.current != null) return;
                  const h = el.getBoundingClientRect().height;
                  if (h > 0) rowHeightRef.current = h;
                };
                const isTargetLine = scrollToLine != null && lineNumber === scrollToLine;
                const rowHighlightClass = isTargetLine
                  ? "bg-amber-500/15 border-l-2 border-amber-500"
                  : "";
                return (
                  <tr
                    key={`${lineNumber}-${rowIdx}`}
                    data-line={lineNumber}
                    ref={setRowHeightRef}
                    className={`transition-colors ${rowHighlightClass || "hover:bg-code-line/40"}`}
                  >
                    <td
                      className="px-4 py-0 whitespace-pre-wrap cursor-text select-text align-top"
                    >
                      <HighlightedLine
                        line={line}
                        language={language}
                        highlightTokens={undefined}
                        highlightWord={selectedWord ?? undefined}
                      />
                    </td>
                  </tr>
                );
              }

              const setRowHeightRef = (el: HTMLTableRowElement | null) => {
                if (!el || rowHeightRef.current != null) return;
                const h = el.getBoundingClientRect().height;
                if (h > 0) rowHeightRef.current = h;
              };
              const isBlockStart = isFoldableLanguage && blockEndByStart.has(lineNumber);
              const isCollapsed = isBlockStart && collapsedFoldStarts.has(lineNumber);
              const isTargetLine = scrollToLine != null && lineNumber === scrollToLine;
              const isPermanentEdge =
                permanentHighlightRanges &&
                permanentHighlightRanges.some(
                  (r) => lineNumber === r.start || lineNumber === r.end
                );
              const fn = getFunctionForLine(lineNumber);
              const isFlaggedFunctionEdge =
                fn != null && (lineNumber === fn.startLine || lineNumber === fn.endLine);
              const isHoveredBlockEdge =
                hoveredBlock != null &&
                (lineNumber === hoveredBlock.start || lineNumber === hoveredBlock.end);
              const rowHighlightClass = isTargetLine
                ? "bg-amber-500/35 border-l-2 border-amber-500"
                : isFlaggedFunctionEdge
                  ? "bg-destructive/15 border-l-2 border-destructive/80"
                  : isPermanentEdge
                  ? "bg-destructive/15 border-l-2 border-destructive"
                  : isHoveredBlockEdge
                    ? "bg-primary/15 border-l-2 border-primary/80"
                    : "";
              const fnTitle =
                fn
                  ? [
                      fn.name ? `Função: ${fn.name}` : "Função suspeita",
                      fn.severity ? `Severidade: ${fn.severity}` : null,
                      typeof fn.score === "number" ? `Score: ${fn.score}` : null,
                      fn.reasons && fn.reasons.length ? `Razões: ${fn.reasons.join(" · ")}` : null,
                    ]
                      .filter(Boolean)
                      .join("\n")
                  : undefined;
              return (
                <tr
                  key={`${lineNumber}-${rowIdx}`}
                  data-line={lineNumber}
                  ref={setRowHeightRef}
                  className={`transition-colors ${rowHighlightClass || "hover:bg-code-line/50"}`}
                  title={fnTitle}
                  onMouseEnter={() => {
                    if (!isFoldableLanguage) return;
                    if (line.includes("{")) {
                      const end = blockEndByStart.get(lineNumber);
                      if (end != null) {
                        setHoveredBlock({ start: lineNumber, end });
                        return;
                      }
                    }
                    if (line.includes("}")) {
                      const start = blockStartByEnd.get(lineNumber);
                      if (start != null) {
                        setHoveredBlock({ start, end: lineNumber });
                        return;
                      }
                    }
                    setHoveredBlock(null);
                  }}
                  onMouseLeave={() => {
                    setHoveredBlock(null);
                  }}
                >
                  <td className="w-5 min-w-[20px] border-r border-border/20 p-0 align-middle">
                    {isBlockStart ? (
                      <button
                        type="button"
                        onClick={() => toggleFold(lineNumber)}
                        className="flex h-full w-5 items-center justify-center rounded text-muted-foreground hover:bg-muted hover:text-foreground"
                        aria-label={isCollapsed ? "Expandir bloco" : "Recolher bloco"}
                      >
                        {isCollapsed ? (
                          <ChevronRight className="h-3.5 w-3.5" />
                        ) : (
                          <ChevronDown className="h-3.5 w-3.5" />
                        )}
                      </button>
                    ) : null}
                  </td>
                  <td
                    className="select-none border-r border-border/30 px-3 py-0 text-right text-[11px] text-muted-foreground/50 w-10 cursor-pointer"
                    onClick={() => {
                      if (isFoldableLanguage && isBlockStart) {
                        toggleFold(lineNumber);
                      }
                    }}
                  >
                    {lineNumber}
                  </td>
                  <td
                    className="px-4 py-0 whitespace-pre cursor-text select-text"
                    onDoubleClick={onWordSelect ? handleCodeDoubleClick : undefined}
                  >
                    <HighlightedLine
                      line={line}
                      language={language}
                      highlightTokens={language === "C" ? flaggedIndicators ?? undefined : undefined}
                      highlightWord={selectedWord ?? undefined}
                    />
                  </td>
                </tr>
              );
            })}
            {virtualSlice.bottomPad > 0 ? (
              <tr aria-hidden="true">
                <td
                  colSpan={language === "report" ? 1 : 3}
                  style={{ height: virtualSlice.bottomPad, padding: 0, border: 0 }}
                />
              </tr>
            ) : null}
          </tbody>
        </table>

        {isWindowMode && !hideWindowNotice && (
          <div className="sticky bottom-0 flex items-center justify-between gap-3 border-t border-border bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
            <span>
              A mostrar ±{windowContextLines.toLocaleString()} linhas à volta do marcador. Faça scroll para carregar mais.
            </span>
          </div>
        )}

        {displayLineRanges && displayLineRanges.length > 0 && showDisplayRangesNotice && (
          <div className="sticky bottom-0 flex items-center justify-between gap-3 border-t border-border bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
            <span>A mostrar apenas funções com flag. Descarregue o ficheiro para ver o código completo.</span>
          </div>
        )}

        {shouldLimit && !hideLimitNotice && (
          <div className="sticky bottom-0 flex items-center justify-between gap-3 border-t border-border bg-gradient-to-t from-background to-background/80 px-3 py-2 text-[11px] text-muted-foreground">
            <span>
              A mostrar {maxInitialLines.toLocaleString()} de {totalLines.toLocaleString()} linhas.
            </span>
            <button
              type="button"
              onClick={() => setShowAll(true)}
              className="rounded border border-border bg-secondary px-2 py-1 text-[11px] font-medium text-secondary-foreground hover:bg-secondary/80"
            >
              Mostrar tudo
            </button>
          </div>
        )}
      </div>
    </motion.div>
  );
};


export default CodePanel;