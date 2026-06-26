// --- Módulo: CodePanel.tsx ---
// Painel de código com highlight, fold, janela deslizante e virtualização.

import React, { useRef, useMemo, useState } from "react";
import { motion } from "framer-motion";
import { Maximize2, Download } from "lucide-react";
import type { CodePanelProps } from "./CodePanel/types";
import GeminiAssistDialog from "./CodePanel/GeminiAssistDialog";
import GeminiIcon from "@/components/GeminiIcon";
import { buildCodeExcerpt } from "@/lib/gemini";
import { useCodePanelWindow } from "./CodePanel/useCodePanelWindow";
import { useCodePanelVisibleRows } from "./CodePanel/useCodePanelVisibleRows";
import { useCodePanelFold } from "./CodePanel/useCodePanelFold";
import { useCodePanelVirtualization } from "./CodePanel/useCodePanelVirtualization";
import { useCodePanelScroll } from "./CodePanel/useCodePanelScroll";
import { useCodePanelHighlights } from "./CodePanel/useCodePanelHighlights";
import { useCodePanelDownload } from "./CodePanel/useCodePanelDownload";
import { CodePanelTable } from "./CodePanel/CodePanelTable";
import { CodePanelDownloadDialog } from "./CodePanel/CodePanelDownloadDialog";

// --- Componente principal ---
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
  // --- Estado e refs partilhados ---
  const scrollRef = useRef<HTMLDivElement>(null);
  const rowHeightRef = useRef<number | null>(null);
  const pendingScrollAdjustPxRef = useRef<number>(0);
  const [showAll, setShowAll] = useState(false);
  const [geminiDialogOpen, setGeminiDialogOpen] = useState(false);

  const lines = useMemo(() => code.split("\n"), [code]);
  const totalLines = lines.length;

  // --- Hooks de lógica ---
  const {
    isWindowMode,
    windowStart,
    windowEnd,
    windowSize,
    expandWindow,
    ensureRowHeight,
    handleWheel,
  } = useCodePanelWindow({
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
  });

  const { visibleRows, shouldLimit } = useCodePanelVisibleRows({
    lines,
    totalLines,
    isWindowMode,
    windowStart,
    windowEnd,
    displayLineRanges,
    showAll,
    maxInitialLines,
  });

  const {
    foldedRows,
    collapsedFoldStarts,
    blockEndByStart,
    blockStartByEnd,
    isFoldableLanguage,
    toggleFold,
    hoveredBlock,
    setHoveredBlock,
    handleCodeDoubleClick,
  } = useCodePanelFold({
    lines,
    language,
    visibleRows,
    scrollToLine,
    onWordSelect,
  });

  const { virtualSlice, setScrollTop, setRowHeightFromElement } = useCodePanelVirtualization({
    scrollRef,
    rowHeightRef,
    foldedRows,
    isWindowMode,
    displayLineRanges,
  });

  const { handleScroll } = useCodePanelScroll({
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
  });

  const { getFunctionForLine } = useCodePanelHighlights({ functionHighlights });

  const download = useCodePanelDownload({
    code,
    lines,
    downloadFileName,
    displayLineRanges,
    functionHighlights,
  });

  const geminiCodeExcerpt = useMemo(
    () =>
      buildCodeExcerpt(lines, {
        displayLineRanges,
        windowStart: isWindowMode ? windowStart : null,
        windowEnd: isWindowMode ? windowEnd : null,
        maxInitialLines,
        showAll,
      }),
    [displayLineRanges, isWindowMode, lines, maxInitialLines, showAll, windowEnd, windowStart],
  );

  // --- Render ---
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
              onClick={download.handleDownload}
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

      <CodePanelDownloadDialog
        open={download.downloadDialogOpen}
        onClose={() => download.setDownloadDialogOpen(false)}
        hasFlaggedFunctions={download.hasFlaggedFunctions}
        currentFlaggedRange={download.currentFlaggedRange}
        onDownloadFull={download.downloadFull}
        onDownloadCurrentFlagged={download.downloadCurrentFlagged}
        onDownloadAllFlagged={download.downloadAllFlagged}
      />

      {/* Code area */}
      <div
        ref={scrollRef}
        onScroll={disableScroll ? undefined : handleScroll}
        onWheel={disableScroll ? undefined : handleWheel}
        className={`flex-1 min-h-0 ${disableScroll ? "overflow-hidden" : "overflow-auto"} code-block p-0 ${
          compactHeader ? "min-h-0" : ""
        }`}
      >
        <CodePanelTable
          language={language}
          virtualSlice={virtualSlice}
          scrollToLine={scrollToLine}
          setRowHeightFromElement={setRowHeightFromElement}
          isFoldableLanguage={isFoldableLanguage}
          blockEndByStart={blockEndByStart}
          blockStartByEnd={blockStartByEnd}
          collapsedFoldStarts={collapsedFoldStarts}
          toggleFold={toggleFold}
          hoveredBlock={hoveredBlock}
          setHoveredBlock={setHoveredBlock}
          permanentHighlightRanges={permanentHighlightRanges}
          getFunctionForLine={getFunctionForLine}
          flaggedIndicators={flaggedIndicators}
          selectedWord={selectedWord}
          onWordSelect={onWordSelect}
          handleCodeDoubleClick={handleCodeDoubleClick}
        />
      </div>

      {isWindowMode && !hideWindowNotice && (
        <div className="flex shrink-0 items-center justify-between gap-3 border-t border-border bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
          <span>
            A mostrar ±{windowContextLines.toLocaleString()} linhas à volta do marcador. Faça scroll para carregar mais.
          </span>
        </div>
      )}

      {displayLineRanges && displayLineRanges.length > 0 && showDisplayRangesNotice && (
        <div className="flex shrink-0 items-center justify-between gap-3 border-t border-border bg-muted/50 px-3 py-2 text-[11px] text-muted-foreground">
          <span>A mostrar apenas funções com flag. Descarregue o ficheiro para ver o código completo.</span>
        </div>
      )}

      {shouldLimit && !hideLimitNotice && (
        <div className="flex shrink-0 items-center justify-between gap-3 border-t border-border bg-gradient-to-t from-background to-background/80 px-3 py-2 text-[11px] text-muted-foreground">
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
    </motion.div>
  );
};

export default CodePanel;
