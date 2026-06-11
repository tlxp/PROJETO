import React from "react";
import { ChevronLeft, ChevronRight, Code2, FileCode2, FileText } from "lucide-react";
import CodePanel from "@/components/CodePanel";
import { buildShortFileName } from "@/lib/artifactNaming";
import type { AnalysisResult, FlaggedFunction } from "@/lib/analysis";

type LineRange = { start: number; end: number };

type ResultsGridProps = {
  result: AnalysisResult | null;
  flaggedFunctionsSorted: FlaggedFunction[];
  activeFlaggedFunctionIndex: number;
  activeFlaggedFunction: FlaggedFunction | null;
  onSelectFlaggedFunction: (idx: number) => void;
  scrollToLine: number | null;
  activeCDisplayRange: LineRange[] | undefined;
  highlightedLineRange: LineRange | null;
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
  baseDownloadName: string;
  onExpand: (panel: "c" | "il" | "report") => void;
};

/** Grid de resultados: 3 colunas (C, IL e Relatório) + barra de funções suspeitas. */
const ResultsGrid: React.FC<ResultsGridProps> = ({
  result,
  flaggedFunctionsSorted,
  activeFlaggedFunctionIndex,
  activeFlaggedFunction,
  onSelectFlaggedFunction,
  scrollToLine,
  activeCDisplayRange,
  highlightedLineRange,
  cFunctionHighlights,
  baseDownloadName,
  onExpand,
}) => (
  <div className="grid grid-cols-1 gap-4 lg:grid-cols-3" style={{ height: "calc(100vh - 200px)" }}>
    <div className="flex flex-col min-h-0">
      {flaggedFunctionsSorted.length > 0 && (
        <div className="mb-2 flex items-center justify-between gap-2 rounded-lg border border-border bg-card/70 px-3 py-2 text-[11px] font-mono">
          <span className="text-muted-foreground">
            Funções suspeitas:{" "}
            <span className="text-foreground font-semibold">
              {activeFlaggedFunctionIndex + 1}/{flaggedFunctionsSorted.length}
            </span>
            {activeFlaggedFunction?.name ? (
              <span className="text-muted-foreground"> · {activeFlaggedFunction.name}</span>
            ) : null}
          </span>
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => onSelectFlaggedFunction(activeFlaggedFunctionIndex - 1)}
              className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
              aria-label="Função suspeita anterior"
              disabled={flaggedFunctionsSorted.length <= 1}
            >
              <ChevronLeft className="h-3 w-3" />
            </button>
            <button
              type="button"
              onClick={() => onSelectFlaggedFunction(activeFlaggedFunctionIndex + 1)}
              className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
              aria-label="Próxima função suspeita"
              disabled={flaggedFunctionsSorted.length <= 1}
            >
              <ChevronRight className="h-3 w-3" />
            </button>
          </div>
        </div>
      )}
      <CodePanel
        title="Código C"
        language="C"
        code={result?.cCode ?? ""}
        icon={<Code2 className="h-3.5 w-3.5 text-primary" />}
        scrollToLine={scrollToLine}
        displayLineRanges={(flaggedFunctionsSorted.length > 0 ? activeCDisplayRange : undefined) ?? undefined}
        highlightedLineRange={highlightedLineRange}
        flaggedIndicators={result?.flaggedIndicators ?? undefined}
        functionHighlights={cFunctionHighlights}
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
        maxInitialLines={800}
        showDisplayRangesNotice
        onExpand={() => onExpand("c")}
      />
    </div>
    <CodePanel
      title="IL / Bytecode"
      language="MSIL"
      code={result?.ilCode ?? ""}
      icon={<FileCode2 className="h-3.5 w-3.5 text-accent" />}
      hideLimitNotice
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
      onExpand={() => onExpand("il")}
    />
    <CodePanel
      title="Relatório"
      language="report"
      code={result?.report ?? ""}
      icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
      downloadFileName={
        result?.report != null
          ? buildShortFileName({
              baseName: baseDownloadName,
              kind: "report",
              parts: [],
              ext: "txt",
              maxTotal: 120,
            })
          : undefined
      }
      onExpand={() => onExpand("report")}
    />
  </div>
);

export default ResultsGrid;
