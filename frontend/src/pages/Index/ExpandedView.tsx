// --- Módulo: ExpandedView.tsx ---
// Vista expandida com navegação, código e referências em ecrã inteiro.

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronLeft, ChevronRight, Code2, FileCode2, FileSearch, FileText, X } from "lucide-react";
import CodePanel from "@/components/CodePanel";
import { buildShortFileName } from "@/lib/artifactNaming";
import type {
  AnalysisResult,
  ExpandedPanel,
  FlaggedFunction,
  ReportChapter,
  WordStats,
} from "@/lib/analysis";

type LineRange = { start: number; end: number };

type ExpandedViewProps = {
  expandedPanel: Exclude<ExpandedPanel, null>;
  result: AnalysisResult | null;
  baseDownloadName: string;
  onClose: () => void;
  onOpenSnippets: () => void;

  flaggedFunctionsSorted: FlaggedFunction[];
  flaggedFunctionsOrder: "code" | "severity";
  onOrderChange: (order: "code" | "severity") => void;
  activeFlaggedFunctionIndex: number;
  activeCFunctionId: string | null;
  onSelectFlaggedFunction: (idx: number, opts?: { scroll?: boolean }) => void;
  onViewportLineChange: (line: number) => void;

  reportChapters: ReportChapter[];
  expandedReportText: string;
  expandedReportTitle: string;
  isReportExpanded: boolean;
  scrollToLine: number | null;
  onScrollToLine: (line: number) => void;
  highlightedLineRange: LineRange | null;
  activeCDisplayRange: LineRange[] | undefined;
  cFunctionHighlights: {
    id: string;
    name: string;
    startLine: number;
    endLine: number;
    severity?: string;
    score?: number;
    indicators?: string[];
    reasons?: string[];
  }[];

  selectedWord: string | null;
  onWordSelect: (word: string) => void;
  onClearSelectedWord: () => void;
  wordStats: WordStats | null;
  showReferences: boolean;
  referencesProgress: number;
  onOpenXrefExplorer: () => void;

  leftColWidth: number;
  rightColWidth: number;
  onLeftResizeStart: (e: React.MouseEvent) => void;
  onRightResizeStart: (e: React.MouseEvent) => void;
  geminiAllowMock?: boolean;
};

// --- Componente ---
const ExpandedView: React.FC<ExpandedViewProps> = ({
  expandedPanel,
  result,
  baseDownloadName,
  onClose,
  onOpenSnippets,
  flaggedFunctionsSorted,
  flaggedFunctionsOrder,
  onOrderChange,
  activeFlaggedFunctionIndex,
  activeCFunctionId,
  onSelectFlaggedFunction,
  onViewportLineChange,
  reportChapters,
  expandedReportText,
  expandedReportTitle,
  isReportExpanded,
  scrollToLine,
  onScrollToLine,
  highlightedLineRange,
  activeCDisplayRange,
  cFunctionHighlights,
  selectedWord,
  onWordSelect,
  onClearSelectedWord,
  wordStats,
  showReferences,
  referencesProgress,
  onOpenXrefExplorer,
  leftColWidth,
  rightColWidth,
  onLeftResizeStart,
  onRightResizeStart,
  geminiAllowMock = false,
}) => (
  <motion.div
    initial={{ opacity: 0 }}
    animate={{ opacity: 1 }}
    exit={{ opacity: 0 }}
    className="fixed inset-0 z-50 flex bg-background"
  >
    {/* Barra superior com título, botões de trechos (só no painel C) e fechar */}
    <div className="absolute left-0 right-0 top-0 z-10 flex items-center justify-between border-b border-border bg-card/95 px-4 py-2 backdrop-blur-sm">
      <span className="font-mono text-sm font-medium text-muted-foreground">
        {expandedPanel === "c" && "Código C"}
        {expandedPanel === "il" && "IL / Bytecode"}
        {isReportExpanded && expandedReportTitle}
      </span>
      <div className="flex items-center gap-2">
        {expandedPanel === "c" && (
          <button
            type="button"
            onClick={onOpenSnippets}
            className="inline-flex items-center gap-1 rounded border border-primary/40 bg-primary/10 px-2 py-1.5 text-[11px] font-mono text-primary hover:bg-primary/20"
          >
            <FileSearch className="h-3.5 w-3.5" />
            Ver antes / depois da deobfuscação
          </button>
        )}
        <button
          type="button"
          onClick={onClose}
          className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground"
          aria-label="Fechar"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>

    {/* Coluna esquerda: navegação/contexto (largura redimensionável) */}
    <div
      className="flex shrink-0 flex-col border-r border-border bg-card/80 pt-12"
      style={{ width: leftColWidth }}
    >
      <div className="border-b border-border px-3 py-2">
        <h3 className="font-mono text-xs font-semibold text-muted-foreground">
          {expandedPanel === "c" && "Funções suspeitas"}
          {expandedPanel === "il" && "Navegação"}
          {isReportExpanded && "Marcadores do relatório"}
        </h3>
      </div>
      <div className="flex-1 overflow-auto p-2">
        {expandedPanel === "c" ? (
          flaggedFunctionsSorted.length === 0 ? (
            <p className="text-xs text-muted-foreground">
              Nenhuma função suspeita identificada.
            </p>
          ) : (
            <div className="space-y-2">
              <div className="flex items-center justify-between gap-2 rounded-md border border-border bg-card/60 px-2 py-1.5 text-[11px] font-mono text-muted-foreground">
                <span className="select-none">Ordem</span>
                <select
                  value={flaggedFunctionsOrder}
                  onChange={(e) => onOrderChange(e.target.value as "code" | "severity")}
                  className="rounded border border-border bg-card px-2 py-1 text-[11px] text-foreground"
                  aria-label="Ordenação das funções suspeitas"
                >
                  <option value="code">Chegada no código</option>
                  <option value="severity">Severidade (score)</option>
                </select>
              </div>
              <div className="flex items-center justify-between gap-2 rounded-md border border-border bg-card/60 px-2 py-1.5 text-[11px] font-mono text-muted-foreground">
                <span>
                  {activeFlaggedFunctionIndex + 1}/{flaggedFunctionsSorted.length}
                </span>
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    onClick={() =>
                      onSelectFlaggedFunction(activeFlaggedFunctionIndex - 1, { scroll: true })
                    }
                    className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                    aria-label="Função anterior"
                    disabled={flaggedFunctionsSorted.length <= 1}
                  >
                    <ChevronLeft className="h-3 w-3" />
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      onSelectFlaggedFunction(activeFlaggedFunctionIndex + 1, { scroll: true })
                    }
                    className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
                    aria-label="Próxima função"
                    disabled={flaggedFunctionsSorted.length <= 1}
                  >
                    <ChevronRight className="h-3 w-3" />
                  </button>
                </div>
              </div>
              <ul className="space-y-1">
                {flaggedFunctionsSorted.map((f, idx) => (
                  <li key={`${f.id ?? ""}-${f.name}-${f.startLine}-${f.endLine}-${idx}`}>
                    <button
                      type="button"
                      onClick={() => {
                        onSelectFlaggedFunction(idx, { scroll: true });
                      }}
                      className={`w-full rounded-md px-2 py-1.5 text-left text-[11px] text-foreground transition-colors hover:bg-secondary/80 flex flex-col items-start gap-0.5 ${
                        activeCFunctionId &&
                        activeCFunctionId === ((f.id && f.id.trim()) || `${f.name}:${f.startLine}-${f.endLine}`)
                          ? "bg-primary/10 border border-primary/30"
                          : "border border-transparent"
                      }`}
                    >
                      <span className="font-medium">
                        {idx + 1}. {f.name || "função suspeita"} (linhas {f.startLine}–{f.endLine})
                      </span>
                      {(typeof f.score === "number" || f.severity) && (
                        <span className="text-[10px] text-muted-foreground">
                          {f.severity ? `Severidade: ${f.severity}` : null}
                          {f.severity && typeof f.score === "number" ? " · " : null}
                          {typeof f.score === "number" ? `Score (0-100): ${f.score}/100` : null}
                          {typeof f.scoreRaw === "number" && typeof f.score === "number" && f.scoreRaw > 100
                            ? ` · bruto: ${f.scoreRaw}`
                            : null}
                        </span>
                      )}
                      {f.indicators && f.indicators.length > 0 && (
                        <span className="text-[10px] text-muted-foreground">
                          Indicadores: {Array.from(new Set(f.indicators)).join(", ")}
                        </span>
                      )}
                      {f.reasons && f.reasons.length > 0 && (() => {
                        const firstNonIndicators = f.reasons.find((r) => {
                          const t = (r ?? "").toString().trim();
                          if (!t) return false;
                          return !/^indicadores?\s*:/i.test(t);
                        });
                        return firstNonIndicators ? (
                          <span className="text-[10px] text-muted-foreground">
                            {firstNonIndicators}
                          </span>
                        ) : null;
                      })()}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )
        ) : isReportExpanded ? (
          reportChapters.length === 0 ? (
            <p className="text-xs text-muted-foreground">Nenhum marcador no relatório.</p>
          ) : (
            <ul className="space-y-1">
              {reportChapters.map((chapter, idx) => (
                <li key={`${chapter.label}-${chapter.line}-${idx}`}>
                  <button
                    type="button"
                    onClick={() => onScrollToLine(chapter.line)}
                    className="w-full rounded-md px-2 py-1.5 text-left text-[11px] text-foreground transition-colors hover:bg-secondary/80 hover:text-foreground"
                  >
                    {chapter.label}
                  </button>
                </li>
              ))}
            </ul>
          )
        ) : (
          <p className="text-xs text-muted-foreground">
            Navegação específica não disponível para este painel.
          </p>
        )}
      </div>
    </div>
    <div
      role="separator"
      aria-label="Redimensionar coluna esquerda"
      onMouseDown={onLeftResizeStart}
      className="w-1 shrink-0 cursor-col-resize select-none border-r border-border bg-transparent hover:bg-primary/30 transition-colors"
    />

    {/* Coluna do meio: código (preenche o espaço; largura definida pelo utilizador) */}
    <div className="flex min-w-0 flex-1 flex-col pt-12">
      {expandedPanel === "c" && (
        <CodePanel
          title="Código C"
          language="C"
          code={result?.cCode ?? ""}
          icon={<Code2 className="h-3.5 w-3.5 text-primary" />}
          scrollToLine={scrollToLine}
          compactHeader
          displayLineRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
          highlightedLineRange={highlightedLineRange}
          permanentHighlightRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
          flaggedIndicators={result?.flaggedIndicators ?? undefined}
          functionHighlights={cFunctionHighlights}
          onViewportLineChange={onViewportLineChange}
          selectedWord={selectedWord ?? undefined}
          onWordSelect={onWordSelect}
          downloadFileName={
            result?.cCode != null
              ? buildShortFileName({
                  baseName: baseDownloadName,
                  kind: "c",
                  parts: [],
                  ext: "c",
                  maxTotal: 120,
                })
              : undefined
          }
          maxInitialLines={2000}
          geminiAssist
          geminiAllowMock={geminiAllowMock}
        />
      )}
      {expandedPanel === "il" && (
        <CodePanel
          title="IL / Bytecode"
          language="MSIL"
          code={result?.ilCode ?? ""}
          icon={<FileCode2 className="h-3.5 w-3.5 text-accent" />}
          scrollToLine={scrollToLine}
          compactHeader
          highlightedLineRange={highlightedLineRange}
          selectedWord={selectedWord ?? undefined}
          onWordSelect={onWordSelect}
          downloadFileName={
            result?.ilCode != null
              ? buildShortFileName({
                  baseName: baseDownloadName,
                  kind: "il",
                  parts: [],
                  ext: "il",
                  maxTotal: 120,
                })
              : undefined
          }
        />
      )}
      {isReportExpanded && (
        <CodePanel
          title={expandedReportTitle}
          language="report"
          code={expandedReportText}
          icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
          scrollToLine={scrollToLine}
          compactHeader
          downloadFileName={
            expandedReportText
              ? buildShortFileName({
                  baseName: baseDownloadName,
                  kind: "report",
                  parts:
                    expandedPanel === "report-vm"
                      ? ["vm"]
                      : expandedPanel === "report-static"
                        ? ["static"]
                        : [],
                  ext: "txt",
                  maxTotal: 120,
                })
              : undefined
          }
        />
      )}
    </div>

    {/* Resizer + coluna direita: só aparecem quando uma palavra está selecionada */}
    <AnimatePresence>
      {showReferences && (
        <>
          <div
            role="separator"
            aria-label="Redimensionar coluna direita"
            onMouseDown={onRightResizeStart}
            className="w-1 shrink-0 cursor-col-resize select-none border-r border-border bg-transparent hover:bg-primary/30 transition-colors"
          />
          <motion.div
            initial={{ opacity: 0, x: 40 }}
            animate={{ opacity: 0.4 + referencesProgress * 0.6, x: 0 }}
            exit={{ opacity: 0, x: 40 }}
            transition={{ duration: 0.25 }}
            className="flex shrink-0 flex-col border-l border-border bg-card/80 pt-12"
            style={{ width: rightColWidth }}
          >
            <div className="flex items-center justify-between border-b border-border px-3 py-2">
              <h3 className="font-mono text-xs font-semibold text-muted-foreground">
                Referências
              </h3>
              <button
                type="button"
                onClick={onClearSelectedWord}
                className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                aria-label="Fechar referências"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
            <div className="flex flex-1 flex-col gap-3 overflow-auto p-3">
              <div className="rounded border border-border/50 bg-muted/30 px-2 py-1.5 font-mono text-sm font-medium text-foreground break-all">
                {selectedWord}
              </div>
              {wordStats && (
                <>
                  <div className="text-[11px] text-muted-foreground">
                    {expandedPanel === "c" ? (
                      <>
                        <button
                          type="button"
                          onClick={onOpenXrefExplorer}
                          className="group inline rounded px-0.5 -mx-0.5 hover:bg-primary/15 transition-colors align-baseline"
                          title="Abrir mapa de xrefs (pseudo-C) num novo separador"
                        >
                          <span className="font-medium text-foreground tabular-nums group-hover:text-primary group-hover:underline decoration-primary/60 underline-offset-2">
                            {wordStats.mentions}
                          </span>
                        </button>{" "}
                        menção
                        {wordStats.mentions !== 1 ? "ões" : ""} no código
                      </>
                    ) : (
                      <>
                        <span className="font-medium text-foreground">{wordStats.mentions}</span>{" "}
                        menção
                        {wordStats.mentions !== 1 ? "ões" : ""} no código
                      </>
                    )}
                  </div>
                  {wordStats.inferredType && (
                    <div className="text-[11px] text-muted-foreground">
                      Tipo: <span className="text-foreground">{wordStats.inferredType}</span>
                    </div>
                  )}
                  <div className="text-[11px] text-muted-foreground">
                    Em{" "}
                    <span className="font-medium text-foreground">{wordStats.functionsCount}</span>{" "}
                    {wordStats.functionsCount !== 1 ? "funções" : "função"}
                  </div>
                  {expandedPanel === "c" && wordStats.maliciousCount > 0 && (
                    <div className="text-[11px] text-destructive">
                      Em{" "}
                      <span className="font-semibold">{wordStats.maliciousCount}</span>{" "}
                      {wordStats.maliciousCount !== 1 ? "funções suspeitas" : "função suspeita"}
                    </div>
                  )}
                </>
              )}
            </div>
            {/* Barra de tempo fluida no fundo da coluna */}
            <div className="mt-auto px-3 pb-2 pt-1">
              <div className="h-1.5 w-full rounded-full bg-border/40 overflow-hidden">
                <motion.div
                  className="h-full bg-primary"
                  animate={{ width: `${referencesProgress * 100}%` }}
                  transition={{ duration: 0.2, ease: "linear" }}
                />
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  </motion.div>
);

export default ExpandedView;
