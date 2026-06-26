// --- Módulo: useCodePanelWindow.ts ---
// Modo janela deslizante (windowStart/End, expandWindow, wheel).

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { RefObject, MutableRefObject, WheelEvent } from "react";

// --- Tipos ---
export type UseCodePanelWindowOptions = {
  scrollRef: RefObject<HTMLDivElement | null>;
  rowHeightRef: MutableRefObject<number | null>;
  pendingScrollAdjustPxRef: MutableRefObject<number>;
  totalLines: number;
  windowFocusLine?: number | null;
  windowContextLines: number;
  windowChunkLines: number;
  windowMaxLines: number;
  onWindowRangeChange?: (range: { start: number; end: number; totalLines: number }) => void;
  setShowAll: (value: boolean) => void;
};

// --- Hook ---
export function useCodePanelWindow({
  scrollRef,
  rowHeightRef,
  pendingScrollAdjustPxRef,
  totalLines,
  windowFocusLine,
  windowContextLines,
  windowChunkLines,
  windowMaxLines,
  onWindowRangeChange,
  setShowAll,
}: UseCodePanelWindowOptions) {
  const [windowStart, setWindowStart] = useState<number | null>(null);
  const [windowEnd, setWindowEnd] = useState<number | null>(null);
  const lastShiftAtRef = useRef<number>(0);
  const lastWheelShiftAtRef = useRef<number>(0);
  const wheelRemainderPxRef = useRef<number>(0);

  const isWindowMode = windowFocusLine != null && windowFocusLine >= 1;
  const windowSize = Math.max(1, windowContextLines * 2 + 1);

  const ensureRowHeight = useCallback((): number => {
    if (rowHeightRef.current != null && rowHeightRef.current > 0) return rowHeightRef.current;
    const el = scrollRef.current;
    if (!el) return 18;
    const tr = el.querySelector<HTMLTableRowElement>("tr[data-line]");
    if (!tr) return 18;
    const h = tr.getBoundingClientRect().height;
    if (h > 0) rowHeightRef.current = h;
    return rowHeightRef.current ?? 18;
  }, [rowHeightRef, scrollRef]);

  const expandWindow = useCallback(
    (dir: "down" | "up", chunkOverride?: number) => {
      if (!isWindowMode || windowStart == null || windowEnd == null) return;
      if (totalLines <= windowSize) return;

      const now = Date.now();
      if (now - lastShiftAtRef.current < 35) return;

      const curSize = windowEnd - windowStart + 1;
      const baseChunk = Math.max(1, Math.floor(windowChunkLines));
      const chunk = Math.max(baseChunk, Math.min(400, Math.floor(chunkOverride ?? baseChunk)));
      const rowH = rowHeightRef.current ?? 18;

      if (dir === "down" && windowEnd < totalLines) {
        const newEnd = Math.min(totalLines, windowEnd + chunk);
        const newStart = Math.max(1, newEnd - curSize + 1);
        if (newStart !== windowStart || newEnd !== windowEnd) {
          const deltaStart = newStart - windowStart;
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
          const deltaStart = newStart - windowStart;
          pendingScrollAdjustPxRef.current += -deltaStart * rowH;
          lastShiftAtRef.current = now;
          setWindowStart(newStart);
          setWindowEnd(newEnd);
        }
      }
    },
    [
      isWindowMode,
      pendingScrollAdjustPxRef,
      rowHeightRef,
      totalLines,
      windowChunkLines,
      windowEnd,
      windowSize,
      windowStart,
    ],
  );

  const shiftWindowByWheel = useCallback(
    (direction: "up" | "down", linesToShift: number) => {
      if (!isWindowMode || windowStart == null || windowEnd == null) return;
      if (totalLines <= windowSize) return;
      const now = Date.now();
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
    [
      ensureRowHeight,
      isWindowMode,
      pendingScrollAdjustPxRef,
      totalLines,
      windowEnd,
      windowMaxLines,
      windowSize,
      windowStart,
    ],
  );

  const handleWheel = useCallback(
    (e: WheelEvent<HTMLDivElement>) => {
      if (!isWindowMode) return;

      const rowH = ensureRowHeight();

      if (e.deltaY > 0) {
        const px = e.deltaY + wheelRemainderPxRef.current;
        const denom = Math.max(8, rowH);
        const lines = Math.trunc(Math.abs(px) / denom);
        wheelRemainderPxRef.current = px - Math.sign(px) * lines * denom;
        if (lines <= 0) return;
        shiftWindowByWheel("down", lines);
        return;
      }

      if (e.deltaY < 0) {
        wheelRemainderPxRef.current = 0;
        shiftWindowByWheel("up", 1);
      }
    },
    [ensureRowHeight, isWindowMode, shiftWindowByWheel],
  );

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
  }, [isWindowMode, setShowAll, totalLines, windowContextLines, windowFocusLine, windowSize]);

  useEffect(() => {
    if (!isWindowMode || !onWindowRangeChange) return;
    if (windowStart == null || windowEnd == null) return;
    onWindowRangeChange({ start: windowStart, end: windowEnd, totalLines });
  }, [isWindowMode, onWindowRangeChange, totalLines, windowEnd, windowStart]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const adj = pendingScrollAdjustPxRef.current;
    if (adj !== 0) {
      el.scrollTop += adj;
      pendingScrollAdjustPxRef.current = 0;
    }
  }, [pendingScrollAdjustPxRef, scrollRef, windowEnd, windowStart]);

  return {
    isWindowMode,
    windowStart,
    windowEnd,
    windowSize,
    expandWindow,
    ensureRowHeight,
    handleWheel,
  };
}
