// --- Módulo: CodePanelTable.tsx ---
// Tabela virtualizada de linhas de código.

import React from "react";
import { ChevronRight, ChevronDown } from "lucide-react";
import type { DisplayLineRange, FunctionHighlight } from "./types";
import type { VirtualSlice } from "./useCodePanelVirtualization";
import { HighlightedLine } from "./HighlightedLine";

// --- Tipos ---
export type CodePanelTableProps = {
  language: string;
  virtualSlice: VirtualSlice;
  scrollToLine?: number | null;
  setRowHeightFromElement: (el: HTMLTableRowElement | null) => void;
  isFoldableLanguage: boolean;
  blockEndByStart: Map<number, number>;
  blockStartByEnd: Map<number, number>;
  collapsedFoldStarts: Set<number>;
  toggleFold: (startLine: number) => void;
  hoveredBlock: { start: number; end: number } | null;
  setHoveredBlock: (block: { start: number; end: number } | null) => void;
  permanentHighlightRanges?: DisplayLineRange[] | null;
  getFunctionForLine: (lineNumber: number) => FunctionHighlight | null;
  flaggedIndicators?: string[] | null;
  selectedWord?: string | null;
  onWordSelect?: (word: string) => void;
  handleCodeDoubleClick: () => void;
};

// --- Componente ---
export const CodePanelTable: React.FC<CodePanelTableProps> = ({
  language,
  virtualSlice,
  scrollToLine,
  setRowHeightFromElement,
  isFoldableLanguage,
  blockEndByStart,
  blockStartByEnd,
  collapsedFoldStarts,
  toggleFold,
  hoveredBlock,
  setHoveredBlock,
  permanentHighlightRanges,
  getFunctionForLine,
  flaggedIndicators,
  selectedWord,
  onWordSelect,
  handleCodeDoubleClick,
}) => (
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

        if (language === "report") {
          const isTargetLine = scrollToLine != null && lineNumber === scrollToLine;
          const rowHighlightClass = isTargetLine
            ? "bg-amber-500/15 border-l-2 border-amber-500"
            : "";
          return (
            <tr
              key={`${lineNumber}-${rowIdx}`}
              data-line={lineNumber}
              ref={setRowHeightFromElement}
              className={`transition-colors ${rowHighlightClass || "hover:bg-code-line/40"}`}
            >
              <td className="px-4 py-0 whitespace-pre-wrap cursor-text select-text align-top">
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

        const isBlockStart = isFoldableLanguage && blockEndByStart.has(lineNumber);
        const isCollapsed = isBlockStart && collapsedFoldStarts.has(lineNumber);
        const isTargetLine = scrollToLine != null && lineNumber === scrollToLine;
        const isPermanentEdge =
          permanentHighlightRanges &&
          permanentHighlightRanges.some((r) => lineNumber === r.start || lineNumber === r.end);
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
        const fnTitle = fn
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
            ref={setRowHeightFromElement}
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
                highlightTokens={language === "C" ? (flaggedIndicators ?? undefined) : undefined}
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
);
