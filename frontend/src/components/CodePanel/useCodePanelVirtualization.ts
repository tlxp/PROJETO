// --- Módulo: useCodePanelVirtualization.ts ---
// scrollTop, viewport e virtualSlice.

import { useCallback, useLayoutEffect, useMemo, useState } from "react";
import type { DisplayLineRange, Row } from "./types";
import type { RefObject, MutableRefObject } from "react";

// --- Constantes ---
const VIRTUALIZE_THRESHOLD = 150;
const VIRTUAL_OVERSCAN = 20;
const DEFAULT_ROW_HEIGHT = 18;

// --- Tipos ---
export type UseCodePanelVirtualizationOptions = {
  scrollRef: RefObject<HTMLDivElement | null>;
  rowHeightRef: MutableRefObject<number | null>;
  foldedRows: Row[];
  isWindowMode: boolean;
  displayLineRanges?: DisplayLineRange[] | null;
};

export type VirtualSlice = {
  rows: Row[];
  topPad: number;
  bottomPad: number;
  startIdx: number;
};

// --- Hook ---
export function useCodePanelVirtualization({
  scrollRef,
  rowHeightRef,
  foldedRows,
  isWindowMode,
  displayLineRanges,
}: UseCodePanelVirtualizationOptions) {
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(0);

  const shouldVirtualize =
    !isWindowMode && !displayLineRanges?.length && foldedRows.length > VIRTUALIZE_THRESHOLD;

  const virtualSlice = useMemo<VirtualSlice>(() => {
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
  }, [foldedRows, rowHeightRef, scrollTop, shouldVirtualize, viewportHeight]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const update = () => setViewportHeight(el.clientHeight);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [scrollRef]);

  const setRowHeightFromElement = useCallback(
    (el: HTMLTableRowElement | null) => {
      if (!el || rowHeightRef.current != null) return;
      const h = el.getBoundingClientRect().height;
      if (h > 0) rowHeightRef.current = h;
    },
    [rowHeightRef],
  );

  return {
    scrollTop,
    setScrollTop,
    viewportHeight,
    virtualSlice,
    setRowHeightFromElement,
  };
}
