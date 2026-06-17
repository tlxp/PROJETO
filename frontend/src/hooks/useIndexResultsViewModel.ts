import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent } from "react";
import { apiFetch } from "@/lib/api";
import { isValidIdentifier } from "@/lib/identifiers";
import { openXrefExplorerTab, writeXrefSession } from "@/lib/cCodeXref";
import {
  clampFlaggedFunctionsToCode,
  extractObfuscationIndicatorsFromReport,
  flaggedFunctionsSignature,
  getBlockContainingLine,
  getCDisplayRanges,
  getWordStats,
  isFlaggedRangeInCode,
  parseReportCategories,
  parseReportChapters,
  parseReportResumoLines,
  getDisplayVmReport,
  parseSnippetFileSections,
  resolveFlaggedFunctionId,
  zipSnippetPairs,
  type AnalysisResult,
  type ExpandedPanel,
  type FlaggedFunction,
} from "@/lib/analysis";
import {
  DEFAULT_LEFT_COL_WIDTH,
  DEFAULT_RIGHT_COL_WIDTH,
  MAX_COL_WIDTH,
  MIN_COL_WIDTH,
  REFERENCES_TIMEOUT_MS,
} from "@/pages/Index/constants";
import type { SnippetModalState } from "@/pages/Index/SnippetModal";

type UseIndexResultsViewModelArgs = {
  result: AnalysisResult | null;
  file: File | null;
  currentJobId: string | null;
};

export function useIndexResultsViewModel({ result, file, currentJobId }: UseIndexResultsViewModelArgs) {
  const [expandedPanel, setExpandedPanel] = useState<ExpandedPanel>(null);
  const [scrollToLine, setScrollToLine] = useState<number | null>(null);
  const [selectedWord, setSelectedWord] = useState<string | null>(null);
  const [leftColWidth, setLeftColWidth] = useState(DEFAULT_LEFT_COL_WIDTH);
  const [rightColWidth, setRightColWidth] = useState(DEFAULT_RIGHT_COL_WIDTH);
  const resizeRef = useRef<{
    side: "left" | "right";
    startX: number;
    startLeft: number;
    startRight: number;
  } | null>(null);
  const [referencesRemainingMs, setReferencesRemainingMs] = useState<number>(0);
  const referencesTimerRef = useRef<number | null>(null);
  const [overviewCategoryIndex, setOverviewCategoryIndex] = useState(0);
  const [activeCFunctionId, setActiveCFunctionId] = useState<string | null>(null);
  const [activeFlaggedFunctionIndex, setActiveFlaggedFunctionIndex] = useState<number>(0);
  const [flaggedFunctionsOrder, setFlaggedFunctionsOrder] = useState<"code" | "severity">("code");
  const suppressAutoScrollRef = useRef(false);
  const [snippetModal, setSnippetModal] = useState<SnippetModalState>({
    open: false,
    title: "",
    pairs: [],
    currentIndex: 0,
  });

  const resetViewState = useCallback(() => {
    setExpandedPanel(null);
    setScrollToLine(null);
    setSelectedWord(null);
    setOverviewCategoryIndex(0);
  }, []);

  const reportCategories = useMemo(
    () => parseReportCategories(result?.report ?? ""),
    [result?.report]
  );

  const reportChapters = useMemo(
    () => parseReportChapters(result?.report ?? ""),
    [result?.report]
  );

  const reportResumoLines = useMemo(
    () => parseReportResumoLines(result?.report ?? ""),
    [result?.report]
  );

  useEffect(() => {
    setOverviewCategoryIndex(0);
  }, [result?.report]);

  const cCodeLineCount = useMemo(
    () => (result?.cCode ? result.cCode.split("\n").length : 0),
    [result?.cCode]
  );

  const flaggedFunctionsInCode = useMemo(
    () => clampFlaggedFunctionsToCode(result?.cCode ?? "", result?.flaggedFunctions),
    [result?.cCode, result?.flaggedFunctions]
  );

  const flaggedFunctionsSorted = useMemo(() => {
    const src = flaggedFunctionsInCode.filter((f) => f && f.startLine > 0 && f.endLine > 0);
    const arr = [...src];
    if (flaggedFunctionsOrder === "severity") {
      return arr.sort((a, b) => {
        const sa = typeof a.score === "number" ? a.score : Number.NEGATIVE_INFINITY;
        const sb = typeof b.score === "number" ? b.score : Number.NEGATIVE_INFINITY;
        return sb - sa || a.startLine - b.startLine || a.endLine - b.endLine;
      });
    }
    return arr.sort((a, b) => a.startLine - b.startLine || a.endLine - b.endLine);
  }, [flaggedFunctionsInCode, flaggedFunctionsOrder]);

  const flaggedFunctionsListSignature = useMemo(
    () => flaggedFunctionsSignature(flaggedFunctionsSorted),
    [flaggedFunctionsSorted]
  );

  useEffect(() => {
    if (!activeCFunctionId || !flaggedFunctionsSorted.length) return;
    const idx = flaggedFunctionsSorted.findIndex(
      (f) => resolveFlaggedFunctionId(f) === activeCFunctionId
    );
    if (idx >= 0 && idx !== activeFlaggedFunctionIndex) {
      suppressAutoScrollRef.current = true;
      setActiveFlaggedFunctionIndex(idx);
    }
  }, [activeCFunctionId, activeFlaggedFunctionIndex, flaggedFunctionsListSignature, flaggedFunctionsSorted]);

  const getFlaggedFunctionIndexForLine = useCallback(
    (line: number): number => {
      if (!flaggedFunctionsSorted.length) return -1;
      let bestIdx = -1;
      let bestLen = Number.POSITIVE_INFINITY;
      let bestStart = -1;
      for (let i = 0; i < flaggedFunctionsSorted.length; i++) {
        const f = flaggedFunctionsSorted[i];
        if (line < f.startLine || line > f.endLine) continue;
        const len = Math.max(0, f.endLine - f.startLine);
        if (len < bestLen || (len === bestLen && f.startLine > bestStart)) {
          bestIdx = i;
          bestLen = len;
          bestStart = f.startLine;
        }
      }
      return bestIdx;
    },
    [flaggedFunctionsSorted]
  );

  useEffect(() => {
    if (flaggedFunctionsSorted.length === 0) {
      setActiveFlaggedFunctionIndex(0);
      setActiveCFunctionId(null);
      return;
    }

    if (activeCFunctionId) {
      const idx = flaggedFunctionsSorted.findIndex(
        (f) => resolveFlaggedFunctionId(f) === activeCFunctionId
      );
      if (idx >= 0) {
        setActiveFlaggedFunctionIndex((prev) => {
          if (prev === idx) return prev;
          suppressAutoScrollRef.current = true;
          return idx;
        });
        return;
      }
    }

    suppressAutoScrollRef.current = true;
    setActiveFlaggedFunctionIndex(0);
    setActiveCFunctionId(resolveFlaggedFunctionId(flaggedFunctionsSorted[0]));
  }, [flaggedFunctionsListSignature, flaggedFunctionsSorted, activeCFunctionId]);

  const activeFlaggedFunction: FlaggedFunction | null = flaggedFunctionsSorted.length
    ? flaggedFunctionsSorted[
        Math.min(
          Math.max(0, activeFlaggedFunctionIndex),
          Math.max(0, flaggedFunctionsSorted.length - 1)
        )
      ]
    : null;

  const activeCDisplayRange = useMemo(() => {
    if (!activeFlaggedFunction || cCodeLineCount <= 0) return undefined;
    if (!isFlaggedRangeInCode(cCodeLineCount, activeFlaggedFunction)) return undefined;
    return [
      {
        start: Math.max(1, activeFlaggedFunction.startLine),
        end: Math.min(
          cCodeLineCount,
          Math.max(activeFlaggedFunction.startLine, activeFlaggedFunction.endLine)
        ),
      },
    ];
  }, [activeFlaggedFunction, cCodeLineCount]);

  const selectFlaggedFunction = useCallback(
    (idx: number, opts?: { scroll?: boolean }) => {
      const scroll = opts?.scroll !== false;
      if (!flaggedFunctionsSorted.length) return;
      const clamped =
        ((idx % flaggedFunctionsSorted.length) + flaggedFunctionsSorted.length) %
        flaggedFunctionsSorted.length;
      const f = flaggedFunctionsSorted[clamped];

      suppressAutoScrollRef.current = !scroll;
      setActiveFlaggedFunctionIndex(clamped);
      setActiveCFunctionId(resolveFlaggedFunctionId(f));

      if (scroll && (expandedPanel === "c" || expandedPanel === null)) {
        setScrollToLine(f.startLine);
      }
    },
    [expandedPanel, flaggedFunctionsSorted]
  );

  useEffect(() => {
    if (!activeCFunctionId || !activeFlaggedFunction) return;
    if (suppressAutoScrollRef.current) {
      suppressAutoScrollRef.current = false;
      return;
    }
    if (expandedPanel !== "c" && expandedPanel !== null) return;
    setScrollToLine(activeFlaggedFunction.startLine);
  }, [activeCFunctionId, activeFlaggedFunction?.startLine, expandedPanel]);

  const cDisplayRanges = useMemo(
    () =>
      getCDisplayRanges(
        result?.cCode ?? "",
        flaggedFunctionsInCode.map((f) => ({
          startLine: f.startLine,
          endLine: f.endLine,
        }))
      ),
    [result?.cCode, flaggedFunctionsInCode]
  );

  const cFunctionHighlights = useMemo(() => {
    const src = flaggedFunctionsInCode.filter((f) => f && f.startLine > 0 && f.endLine > 0);
    return src.map((f) => ({
      id: (f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`,
      name: f.name,
      startLine: f.startLine,
      endLine: f.endLine,
      severity: f.severity,
      score: f.score,
      indicators: f.indicators,
      reasons: f.reasons,
    }));
  }, [flaggedFunctionsInCode]);

  const baseDownloadName = useMemo(
    () => (result?.fileName ?? file?.name ?? "output").replace(/\.[^.]+$/, "") || "output",
    [result?.fileName, file?.name]
  );

  const resultsTitle = result?.fileName ?? file?.name ?? "Resultados";

  const highlightedLineRange = useMemo(() => {
    if (scrollToLine == null || scrollToLine < 1) return null;
    if (result?.cCode && (expandedPanel === "c" || expandedPanel === null)) {
      const block = getBlockContainingLine(result.cCode, scrollToLine);
      return block ?? { start: scrollToLine, end: scrollToLine };
    }
    if (expandedPanel === "il") return { start: scrollToLine, end: scrollToLine };
    return null;
  }, [expandedPanel, result?.cCode, scrollToLine]);

  useEffect(() => {
    if (scrollToLine == null) return;
    const t = setTimeout(() => setScrollToLine(null), 2200);
    return () => clearTimeout(t);
  }, [scrollToLine]);

  const codeForPanel =
    expandedPanel === "c"
      ? result?.cCode ?? ""
      : expandedPanel === "il"
        ? result?.ilCode ?? ""
        : "";

  const wordStats = useMemo(
    () =>
      selectedWord && codeForPanel
        ? getWordStats(
            codeForPanel,
            selectedWord,
            expandedPanel === "c" ? cDisplayRanges ?? undefined : undefined
          )
        : null,
    [selectedWord, codeForPanel, expandedPanel, cDisplayRanges]
  );

  const handleWordSelect = useCallback((word: string) => {
    const w = word.trim();
    if (w.length >= 2 && isValidIdentifier(w)) setSelectedWord(w);
  }, []);

  const openXrefExplorerFromSidebar = useCallback(() => {
    if (!selectedWord || !result?.cCode || expandedPanel !== "c") return;
    if (currentJobId) {
      const href = `/analysis/${encodeURIComponent(currentJobId)}/xref?word=${encodeURIComponent(selectedWord)}`;
      openXrefExplorerTab(href, { forceNewTab: true });
      return;
    }
    try {
      writeXrefSession({
        v: 1,
        code: result.cCode,
        word: selectedWord,
        fileName: baseDownloadName,
        flaggedIndicators: result.flaggedIndicators,
      });
      openXrefExplorerTab(`/xref?word=${encodeURIComponent(selectedWord)}`, { forceNewTab: true });
    } catch {
      /* storage indisponível */
    }
  }, [selectedWord, result?.cCode, result?.flaggedIndicators, expandedPanel, baseDownloadName, currentJobId]);

  const handleOpenSnippets = useCallback(async () => {
    const jobId = currentJobId;
    const reportText = result?.report ?? "";
    const fallbackFromReport = extractObfuscationIndicatorsFromReport(reportText);
    if (!jobId) {
      const fallbackContent = fallbackFromReport
        ? `${fallbackFromReport}\n\n---\nPara ver trechos de código (antes/depois), abra a análise com o link do job (?jobId=...).`
        : "Trechos disponíveis apenas quando a análise é aberta através do link do job (?jobId=...).";
      setSnippetModal({
        open: true,
        title: fallbackFromReport
          ? "Indicadores de ofuscação (do relatório)"
          : "Antes / Depois da deobfuscação",
        pairs: [],
        currentIndex: 0,
        fallbackContent,
      });
      return;
    }
    setSnippetModal((s) => ({ ...s, open: true, title: "A carregar…", pairs: [], currentIndex: 0 }));
    try {
      const encoded = encodeURIComponent(jobId);
      const [resObf, resDeob] = await Promise.all([
        apiFetch(`/api/analysis/${encoded}/artifacts/obfuscated_snippets?variant=obfuscated`),
        apiFetch(`/api/analysis/${encoded}/artifacts/obfuscated_snippets?variant=deobfuscated`),
      ]);
      const textObf = resObf.ok ? await resObf.text() : "";
      const textDeob = resDeob.ok ? await resDeob.text() : "";
      const isIndicatorListObf = /Indicadores de ofuscação detetados/i.test(textObf);
      const isIndicatorListDeob = /Indicadores de ofuscação detetados/i.test(textDeob);
      if (isIndicatorListObf || isIndicatorListDeob) {
        const fallbackContent =
          (textObf || textDeob) +
          "\n\n---\nNão existe ficheiro de trechos de código para este job. Os itens acima são os indicadores que contam para a categoria Obfuscation do score.";
        setSnippetModal({
          open: true,
          title: "Indicadores de ofuscação (categoria Obfuscation)",
          pairs: [],
          currentIndex: 0,
          fallbackContent,
        });
        return;
      }
      const obfSections = parseSnippetFileSections(textObf);
      const deobSections = parseSnippetFileSections(textDeob);
      const pairs = zipSnippetPairs(obfSections, deobSections);
      if (pairs.length > 0) {
        setSnippetModal({ open: true, title: "Antes / Depois da deobfuscação", pairs, currentIndex: 0 });
        return;
      }
      const fallbackContent =
        resObf.ok || resDeob.ok
          ? textObf || textDeob
          : fallbackFromReport
            ? `${fallbackFromReport}\n\n---\nNão existe ficheiro de trechos para este job. Os itens acima são os indicadores que contam para a categoria Obfuscation do score.`
            : "Nenhuns trechos guardados para este job.";
      setSnippetModal({
        open: true,
        title: "Antes / Depois da deobfuscação",
        pairs: [],
        currentIndex: 0,
        fallbackContent,
      });
    } catch (e) {
      setSnippetModal({
        open: true,
        title: "Erro",
        pairs: [],
        currentIndex: 0,
        fallbackContent: e instanceof Error ? e.message : "Erro ao obter trechos.",
      });
    }
  }, [currentJobId, result?.report]);

  useEffect(() => {
    if (!selectedWord) {
      setReferencesRemainingMs(0);
      if (referencesTimerRef.current != null) {
        window.clearInterval(referencesTimerRef.current);
        referencesTimerRef.current = null;
      }
      return;
    }

    setReferencesRemainingMs(REFERENCES_TIMEOUT_MS);
    if (referencesTimerRef.current != null) {
      window.clearInterval(referencesTimerRef.current);
    }
    const id = window.setInterval(() => {
      setReferencesRemainingMs((prev) => {
        const next = prev - 200;
        if (next <= 0) {
          if (referencesTimerRef.current != null) {
            window.clearInterval(referencesTimerRef.current);
            referencesTimerRef.current = null;
          }
          setSelectedWord(null);
          return 0;
        }
        return next;
      });
    }, 200);
    referencesTimerRef.current = id;

    return () => {
      if (referencesTimerRef.current != null) {
        window.clearInterval(referencesTimerRef.current);
        referencesTimerRef.current = null;
      }
    };
  }, [selectedWord]);

  const showReferences =
    (expandedPanel === "c" || expandedPanel === "il") &&
    !!selectedWord &&
    referencesRemainingMs > 0;

  const referencesProgress =
    REFERENCES_TIMEOUT_MS > 0
      ? Math.max(0, Math.min(1, referencesRemainingMs / REFERENCES_TIMEOUT_MS))
      : 0;

  const handleLeftResizeStart = useCallback(
    (e: ReactMouseEvent) => {
      e.preventDefault();
      resizeRef.current = {
        side: "left",
        startX: e.clientX,
        startLeft: leftColWidth,
        startRight: rightColWidth,
      };
      const onMove = (e2: globalThis.MouseEvent) => {
        if (!resizeRef.current || resizeRef.current.side !== "left") return;
        const delta = e2.clientX - resizeRef.current.startX;
        setLeftColWidth(
          Math.min(MAX_COL_WIDTH, Math.max(MIN_COL_WIDTH, resizeRef.current.startLeft + delta))
        );
      };
      const onUp = () => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        resizeRef.current = null;
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    },
    [leftColWidth, rightColWidth]
  );

  const handleRightResizeStart = useCallback(
    (e: ReactMouseEvent) => {
      e.preventDefault();
      resizeRef.current = {
        side: "right",
        startX: e.clientX,
        startLeft: leftColWidth,
        startRight: rightColWidth,
      };
      const onMove = (e2: globalThis.MouseEvent) => {
        if (!resizeRef.current || resizeRef.current.side !== "right") return;
        const delta = e2.clientX - resizeRef.current.startX;
        setRightColWidth(
          Math.min(MAX_COL_WIDTH, Math.max(MIN_COL_WIDTH, resizeRef.current.startRight - delta))
        );
      };
      const onUp = () => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        resizeRef.current = null;
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    },
    [leftColWidth, rightColWidth]
  );

  const handleExpandPanel = useCallback((panel: Exclude<ExpandedPanel, null>) => {
    setScrollToLine(null);
    setExpandedPanel(panel);
  }, []);

  const expandedReportText = useMemo(() => {
    if (expandedPanel === "report-vm") return getDisplayVmReport(result?.vmReport);
    if (expandedPanel === "report-static" || expandedPanel === "report") return result?.report ?? "";
    return "";
  }, [expandedPanel, result?.vmReport, result?.report]);

  const expandedReportChapters = useMemo(
    () => parseReportChapters(expandedReportText),
    [expandedReportText]
  );

  const expandedReportTitle = useMemo(() => {
    if (expandedPanel === "report-vm") return "Relatório VM";
    if (expandedPanel === "report-static") return "Relatório estático";
    if (expandedPanel === "report") return "Relatório";
    return "";
  }, [expandedPanel]);

  const isReportExpanded =
    expandedPanel === "report" ||
    expandedPanel === "report-static" ||
    expandedPanel === "report-vm";

  const handleCloseExpanded = useCallback(() => {
    setExpandedPanel(null);
    setScrollToLine(null);
    setSelectedWord(null);
  }, []);

  const handleViewportLineChange = useCallback(
    (line: number) => {
      const idx = getFlaggedFunctionIndexForLine(line);
      if (idx >= 0 && idx !== activeFlaggedFunctionIndex) {
        selectFlaggedFunction(idx, { scroll: false });
      } else if (idx >= 0) {
        setActiveCFunctionId(resolveFlaggedFunctionId(flaggedFunctionsSorted[idx]));
      }
    },
    [
      getFlaggedFunctionIndexForLine,
      activeFlaggedFunctionIndex,
      selectFlaggedFunction,
      flaggedFunctionsSorted,
    ]
  );

  const navigateSnippet = useCallback((delta: number) => {
    setSnippetModal((s) => ({
      ...s,
      currentIndex:
        s.pairs.length > 0
          ? (s.currentIndex + delta + s.pairs.length) % s.pairs.length
          : 0,
    }));
  }, []);

  return {
    expandedPanel,
    scrollToLine,
    setScrollToLine,
    selectedWord,
    leftColWidth,
    rightColWidth,
    overviewCategoryIndex,
    setOverviewCategoryIndex,
    flaggedFunctionsOrder,
    setFlaggedFunctionsOrder,
    activeFlaggedFunctionIndex,
    activeCFunctionId,
    snippetModal,
    setSnippetModal,
    resetViewState,
    reportCategories,
    reportChapters,
    expandedReportChapters,
    expandedReportText,
    expandedReportTitle,
    isReportExpanded,
    reportResumoLines,
    flaggedFunctionsSorted,
    activeFlaggedFunction,
    activeCDisplayRange,
    selectFlaggedFunction,
    cFunctionHighlights,
    baseDownloadName,
    resultsTitle,
    highlightedLineRange,
    wordStats,
    showReferences,
    referencesProgress,
    handleWordSelect,
    openXrefExplorerFromSidebar,
    handleOpenSnippets,
    handleLeftResizeStart,
    handleRightResizeStart,
    handleExpandPanel,
    handleCloseExpanded,
    handleViewportLineChange,
    navigateSnippet,
    clearSelectedWord: () => setSelectedWord(null),
  };
}
