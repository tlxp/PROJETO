// --- Módulo: useCodePanelScroll.ts ---
// scrollToLine, handleScroll e notificação de viewport.

import { useCallback, useEffect, useRef } from "react";
import type { RefObject, MutableRefObject } from "react";
import type { Row } from "./types";

// --- Tipos ---
export type UseCodePanelScrollOptions = {
  scrollRef: RefObject<HTMLDivElement | null>;
  rowHeightRef: MutableRefObject<number | null>;
  foldedRows: Row[];
  scrollToLine?: number | null;
  isWindowMode: boolean;
  windowStart: number | null;
  windowEnd: number | null;
  windowSize: number;
  totalLines: number;
  expandWindow: (dir: "down" | "up", chunkOverride?: number) => void;
  ensureRowHeight: () => number;
  onViewportLineChange?: (line: number) => void;
  setScrollTop: (top: number) => void;
};

// --- Hook ---
export function useCodePanelScroll({
  scrollRef,
  rowHeightRef,
  foldedRows,
  scrollToLine,
  isWindowMode,
  windowStart,
  windowEnd,
  windowSize,
  totalLines,
  expandWindow,
  ensureRowHeight,
  onViewportLineChange,
  setScrollTop,
}: UseCodePanelScrollOptions) {
  const lastScrollTopRef = useRef<number>(0);
  const lastViewportNotifyAtRef = useRef<number>(0);
  const lastViewportLineRef = useRef<number | null>(null);

  const handleScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const prevTop = lastScrollTopRef.current;
    const curTop = el.scrollTop;
    lastScrollTopRef.current = curTop;
    setScrollTop(curTop);
    const delta = curTop - prevTop;

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
    const rowH = ensureRowHeight();
    const speedLines = Math.max(1, Math.min(200, Math.round(Math.abs(delta) / Math.max(1, rowH))));
    if (delta > 0 && nearBottom) expandWindow("down", speedLines);
    else if (delta < 0 && nearTop) expandWindow("up", speedLines);
  }, [
    ensureRowHeight,
    expandWindow,
    foldedRows,
    isWindowMode,
    onViewportLineChange,
    rowHeightRef,
    scrollRef,
    setScrollTop,
    totalLines,
    windowEnd,
    windowSize,
    windowStart,
  ]);

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
  }, [foldedRows, scrollRef, scrollToLine]);

  return { handleScroll };
}
