import React, { useRef, useEffect, useMemo, useState, useCallback, useLayoutEffect } from "react";
import { motion } from "framer-motion";
import { Maximize2, Download, ChevronRight, ChevronDown } from "lucide-react";

export type DisplayLineRange = { start: number; end: number };

/** Bloco foldável: linha que abre com "{" até à linha que fecha com "}". */
export type FoldBlock = { startLine: number; endLine: number };

type Row =
  | { type: "code"; lineNumber: number; line: string }
  | { type: "gap"; start: number; end: number }
  | { type: "foldPlaceholder"; startLine: number; endLine: number };

interface CodePanelProps {
  title: string;
  language: string;
  code: string;
  icon?: React.ReactNode;
  scrollToLine?: number | null;
  onExpand?: () => void;
  compactHeader?: boolean;
  /** Quando true, remove moldura externa (para embutir num container com border próprio). */
  embedded?: boolean;
  /** Número máximo de linhas a renderizar inicialmente (para ficheiros muito grandes). */
  maxInitialLines?: number;
  /** Mostrar apenas estas faixas de linhas (ex.: funções com flag). Mantém numeração original. */
  displayLineRanges?: DisplayLineRange[] | null;
  /** Nome do ficheiro para o botão "Descarregar" (ex.: "output.c"). Omitir para esconder o botão. */
  downloadFileName?: string | null;
  /**
   * Modo leve: mostra apenas uma janela de linhas à volta desta linha.
   * Útil para clicar num marcador e ver ±N linhas.
   */
  windowFocusLine?: number | null;
  /** Quantas linhas acima/abaixo mostrar no modo janela. Default: 1000. */
  windowContextLines?: number;
  /** Quantas linhas deslocar a janela por vez ao fazer scroll. Default: 400. */
  windowChunkLines?: number;
  /** Intervalo de linhas a destacar temporariamente ao clicar na barra lateral (scroll + destaque que desaparece). */
  highlightedLineRange?: { start: number; end: number } | null;
  /** Intervalos das funções suspeitas: destaque permanente apenas na primeira e última linha de cada. */
  permanentHighlightRanges?: DisplayLineRange[] | null;
  /** Mostrar a mensagem de aviso quando só estão visíveis funções com flag. */
  showDisplayRangesNotice?: boolean;
  /** Keywords/indicadores que levaram à suspeição (ex.: GetAsyncKeyState) — destacados no texto como maliciosos. */
  flaggedIndicators?: string[] | null;
  /** Palavra selecionada (duplo-clique): mostra referências à direita e highlight no código. */
  selectedWord?: string | null;
  /** Callback quando o utilizador seleciona uma palavra (duplo-clique). */
  onWordSelect?: (word: string) => void;
  /** Esconder aviso de limite de linhas e botão "Mostrar tudo". */
  hideLimitNotice?: boolean;
}

/** Encontra todos os blocos { } no código (por linha). */
function getFoldBlocks(lines: string[]): FoldBlock[] {
  const blocks: FoldBlock[] = [];
  const stack: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;
    for (let o = 0; o < opens; o++) stack.push(i + 1);
    for (let c = 0; c < closes; c++) {
      if (stack.length > 0) {
        const start = stack.pop()!;
        blocks.push({ startLine: start, endLine: i + 1 });
      }
    }
  }
  return blocks;
}

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
  highlightedLineRange,
  permanentHighlightRanges,
  flaggedIndicators,
  selectedWord,
  onWordSelect,
  showDisplayRangesNotice = true,
  hideLimitNotice = false,
}) => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showAll, setShowAll] = useState(false);
  const [windowStart, setWindowStart] = useState<number | null>(null);
  const [windowEnd, setWindowEnd] = useState<number | null>(null);
  const [collapsedFoldStarts, setCollapsedFoldStarts] = useState<Set<number>>(new Set());
  const [hoveredBlock, setHoveredBlock] = useState<{ start: number; end: number } | null>(null);
  const rowHeightRef = useRef<number | null>(null);
  const pendingScrollAdjustPxRef = useRef<number>(0);
  const lastShiftAtRef = useRef<number>(0);

  const lines = useMemo(() => code.split("\n"), [code]);
  const totalLines = lines.length;

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

  const handleScroll = useCallback(() => {
    if (!isWindowMode || windowStart == null || windowEnd == null) return;
    const el = scrollRef.current;
    if (!el) return;
    if (totalLines <= windowSize) return;

    const now = Date.now();
    if (now - lastShiftAtRef.current < 150) return;

    const thresholdPx = 260;
    const nearTop = el.scrollTop < thresholdPx;
    const nearBottom = el.scrollHeight - (el.scrollTop + el.clientHeight) < thresholdPx;

    const rowH = rowHeightRef.current ?? 18;
    const curSize = windowEnd - windowStart + 1;
    const chunk = Math.max(50, windowChunkLines);

    if (nearBottom && windowEnd < totalLines) {
      const newEnd = Math.min(totalLines, windowEnd + chunk);
      const newStart = Math.max(1, newEnd - curSize + 1);
      if (newStart !== windowStart || newEnd !== windowEnd) {
        const deltaStart = newStart - windowStart; // >0 remove linhas de cima
        pendingScrollAdjustPxRef.current += -deltaStart * rowH;
        lastShiftAtRef.current = now;
        setWindowStart(newStart);
        setWindowEnd(newEnd);
      }
    } else if (nearTop && windowStart > 1) {
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
  }, [
    isWindowMode,
    totalLines,
    windowChunkLines,
    windowEnd,
    windowSize,
    windowStart,
  ]);

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
    if (lineEl) {
      lineEl.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [scrollToLine, foldedRows]);

  const handleDownload = useCallback(() => {
    if (!downloadFileName) return;
    const blob = new Blob([code], { type: "text/plain;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = downloadFileName;
    a.click();
    URL.revokeObjectURL(a.href);
  }, [code, downloadFileName]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className={`flex flex-1 flex-col overflow-hidden bg-card ${embedded ? "" : "rounded-lg border border-border"}`}
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

      {/* Code area */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className={`flex-1 overflow-auto code-block p-0 ${compactHeader ? "min-h-0" : ""}`}
      >
        <table className="w-full border-collapse">
          <tbody>
            {foldedRows.map((row, idx) => {
              if (row.type === "gap") {
                return (
                  <tr key={`gap-${idx}`} className="bg-muted/30">
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
                  <tr key={`fold-${row.startLine}-${row.endLine}-${idx}`} className="bg-muted/20">
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
                    key={`${lineNumber}-${idx}`}
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
              const isHoveredBlockEdge =
                hoveredBlock != null &&
                (lineNumber === hoveredBlock.start || lineNumber === hoveredBlock.end);
              const rowHighlightClass = isTargetLine
                ? "bg-amber-500/35 border-l-2 border-amber-500"
                : isPermanentEdge
                  ? "bg-destructive/15 border-l-2 border-destructive"
                  : isHoveredBlockEdge
                    ? "bg-primary/15 border-l-2 border-primary/80"
                    : "";
              return (
                <tr
                  key={`${lineNumber}-${idx}`}
                  data-line={lineNumber}
                  ref={setRowHeightRef}
                  className={`transition-colors ${rowHighlightClass || "hover:bg-code-line/50"}`}
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
                    {isWindowMode && language !== "report" ? (
                      <span className="text-foreground">{line}</span>
                    ) : (
                      <HighlightedLine
                        line={line}
                        language={language}
                        highlightTokens={language === "C" ? flaggedIndicators ?? undefined : undefined}
                        highlightWord={selectedWord ?? undefined}
                      />
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>

        {isWindowMode && (
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

const MALICIOUS_CLASS = "bg-destructive/25 text-destructive font-medium";
const SELECTED_WORD_CLASS = "bg-primary/25 text-primary font-medium rounded-sm";

// Simple syntax highlighting + optional highlight of malicious indicators and selected word
const HighlightedLine: React.FC<{
  line: string;
  language: string;
  highlightTokens?: string[] | null;
  highlightWord?: string | null;
}> = ({ line, language, highlightTokens, highlightWord }) => {
  if (language === "report") {
    const trimmed = line.trim();
    if (!trimmed) {
      return <span className="block h-2" />;
    }

    // Linhas de separador (==== / ----) -> linha horizontal suave
    if (/^[=-]{5,}$/.test(trimmed)) {
      return <span className="block border-b border-border/40 my-1" />;
    }

    // Título principal
    if (trimmed.startsWith("RELATÓRIO DE ANÁLISE")) {
      return (
        <span className="block text-sm font-semibold text-code-function mb-1">
          {trimmed}
        </span>
      );
    }

    // Cabeçalhos de secção (RESUMO, INFORMAÇÕES DO FICHEIRO, SCORE DE RISCO, etc.)
    const isAllCaps =
      /^[A-Z0-9ÁÀÂÃÉÈÊÍÓÔÕÚÇ ,./()-]+$/.test(trimmed) && trimmed.length <= 80;
    if (isAllCaps) {
      return (
        <span className="block border-l-2 border-code-function/60 pl-3 text-xs font-semibold text-code-function mt-2 mb-1 tracking-wide">
          {trimmed}
        </span>
      );
    }

    // Bullets / listas
    if (trimmed.startsWith("- ") || trimmed.startsWith("• ") || /^\s*-\s+/.test(line)) {
      return (
        <span className="block pl-4 text-[11px] text-foreground mb-[2px]">
          {trimmed.replace(/^[-•]\s*/, "• ")}
        </span>
      );
    }

    // Linhas de aviso / warning
    if (trimmed.startsWith("⚠") || trimmed.toUpperCase().includes("WARNING") || trimmed.toUpperCase().includes("AVISO")) {
      return (
        <span className="block pl-3 text-[11px] text-code-string mb-[2px]">
          {trimmed}
        </span>
      );
    }
    // Linhas OK / sucesso
    if (trimmed.startsWith("✓") || trimmed.toUpperCase().includes("OK")) {
      return (
        <span className="block pl-3 text-[11px] text-primary mb-[2px]">
          {trimmed}
        </span>
      );
    }
    // Erros / críticas
    if (trimmed.startsWith("✗") || trimmed.toUpperCase().includes("ERROR") || trimmed.toUpperCase().includes("FALHOU")) {
      return (
        <span className="block pl-3 text-[11px] text-destructive mb-[2px]">
          {trimmed}
        </span>
      );
    }

    // Linhas "label: valor" (Score, Nível, Status, Ficheiro, etc.)
    const colonIdx = trimmed.indexOf(":");
    if (colonIdx > 0 && colonIdx < trimmed.length - 1) {
      const label = trimmed.slice(0, colonIdx).trim();
      const value = trimmed.slice(colonIdx + 1).trim();
      return (
        <span className="block pl-2 text-[11px] leading-relaxed">
          <span className="font-semibold text-foreground">{label}:</span>{" "}
          <span className="text-muted-foreground">{value}</span>
        </span>
      );
    }

    // Texto normal do relatório
    return (
      <span className="block pl-1 text-[11px] leading-relaxed text-muted-foreground">
        {trimmed}
      </span>
    );
  }

  // Selected word (duplo-clique) — highlight todas as ocorrências na linha
  const spansWithPriority: { start: number; end: number; className: string; priority: number }[] = [];
  if (highlightWord && highlightWord.length >= 2) {
    const escaped = highlightWord.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp("\\b" + escaped + "\\b", "g");
    let match;
    while ((match = re.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: SELECTED_WORD_CLASS,
        priority: 0,
      });
    }
  }

  // Malicious indicators (GetAsyncKeyState, etc.) — priority 0, override syntax
  if (highlightTokens && highlightTokens.length > 0 && (language === "C" || language === "c")) {
    const tokens = [...highlightTokens].filter((t) => t && t.length >= 2).sort((a, b) => b.length - a.length);
    for (const token of tokens) {
      let pos = 0;
      while (true) {
        const idx = line.indexOf(token, pos);
        if (idx === -1) break;
        spansWithPriority.push({
          start: idx,
          end: idx + token.length,
          className: MALICIOUS_CLASS,
          priority: 0,
        });
        pos = idx + token.length;
      }
    }
  }

  // Basic keyword highlighting for C/C#
  const keywords = /\b(using|namespace|class|public|private|static|void|int|string|return|if|else|for|while|new|var|const|bool|true|false|null|async|await|override|virtual|abstract|interface|enum|struct|readonly|sealed|partial|get|set|this|base|try|catch|throw|finally)\b/g;
  const strings = /(".*?"|'.*?')/g;
  const comments = /(\/\/.*$|\/\*.*?\*\/)/g;
  const numbers = /\b(\d+\.?\d*)\b/g;
  const types = /\b([A-Z][a-zA-Z0-9]*)\b/g;

  let match;
  comments.lastIndex = 0;
  while ((match = comments.exec(line)) !== null) {
    spansWithPriority.push({ start: match.index, end: match.index + match[0].length, className: "text-code-comment", priority: 1 });
  }

  const hasComments = spansWithPriority.some((s) => s.className === "text-code-comment");
  if (!hasComments) {
    strings.lastIndex = 0;
    while ((match = strings.exec(line)) !== null) {
      spansWithPriority.push({ start: match.index, end: match.index + match[0].length, className: "text-code-string", priority: 1 });
    }

    keywords.lastIndex = 0;
    while ((match = keywords.exec(line)) !== null) {
      const overlaps = spansWithPriority.some((s) => match!.index >= s.start && match!.index < s.end);
      if (!overlaps) {
        spansWithPriority.push({ start: match.index, end: match.index + match[0].length, className: "text-code-keyword", priority: 1 });
      }
    }

    types.lastIndex = 0;
    while ((match = types.exec(line)) !== null) {
      const overlaps = spansWithPriority.some((s) => match!.index >= s.start && match!.index < s.end);
      if (!overlaps) {
        spansWithPriority.push({ start: match.index, end: match.index + match[0].length, className: "text-code-type", priority: 1 });
      }
    }

    numbers.lastIndex = 0;
    while ((match = numbers.exec(line)) !== null) {
      const overlaps = spansWithPriority.some((s) => match!.index >= s.start && match!.index < s.end);
      if (!overlaps) {
        spansWithPriority.push({ start: match.index, end: match.index + match[0].length, className: "text-code-number", priority: 1 });
      }
    }
  }

  if (spansWithPriority.length === 0) {
    return <span className="text-foreground">{line}</span>;
  }

  spansWithPriority.sort((a, b) => a.start - b.start);
  const merged: { start: number; end: number; className: string; priority: number }[] = [];
  for (const s of spansWithPriority) {
    for (let i = merged.length - 1; i >= 0; i--) {
      const r = merged[i];
      if (r.end > s.start && r.start < s.end && r.priority > s.priority) {
        merged.splice(i, 1);
      }
    }
    merged.push({ start: s.start, end: s.end, className: s.className, priority: s.priority });
  }
  merged.sort((a, b) => a.start - b.start);

  const elements: React.ReactNode[] = [];
  let lastEnd = 0;
  merged.forEach((span, i) => {
    if (span.start > lastEnd) {
      elements.push(<span key={`t${i}`} className="text-foreground">{line.slice(lastEnd, span.start)}</span>);
    }
    elements.push(<span key={i} className={span.className}>{line.slice(span.start, span.end)}</span>);
    lastEnd = span.end;
  });
  if (lastEnd < line.length) {
    elements.push(<span key="last" className="text-foreground">{line.slice(lastEnd)}</span>);
  }

  return <>{elements}</>;
};

export default CodePanel;
