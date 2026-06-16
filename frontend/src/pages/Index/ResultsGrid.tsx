import React from "react";
import { ChevronLeft, ChevronRight, Code2, FileCode2, FileText, Loader2 } from "lucide-react";
import CodePanel from "@/components/CodePanel";
import { buildShortFileName } from "@/lib/artifactNaming";
import { getDisplayVmReport, type AnalysisResult, type ExpandedPanel, type FlaggedFunction } from "@/lib/analysis";
import { StaticPanelShell } from "./StaticAnalysisLoadingOverlay";

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
  geminiAllowMock?: boolean;
  staticInProgress?: boolean;
  staticProgress?: number | null;
  onExpand: (panel: Exclude<ExpandedPanel, null>) => void;
};

const VmPendingPlaceholder: React.FC = () => (
  <div className="flex h-full min-h-0 flex-col items-center justify-center rounded-lg border border-dashed border-border bg-card/40 px-4 text-center">
    <Loader2 className="mb-2 h-5 w-5 animate-spin text-muted-foreground" />
    <p className="font-mono text-xs text-muted-foreground">Análise na VM em curso…</p>
    <p className="mt-1 font-mono text-[10px] text-muted-foreground/80">
      O relatório dinâmico aparecerá aqui quando a transferência do host terminar.
    </p>
  </div>
);

/** Coluna de relatório: única ou dividida horizontalmente (estático + VM). */
const ReportColumn: React.FC<{
  result: AnalysisResult | null;
  baseDownloadName: string;
  staticInProgress?: boolean;
  staticProgress?: number | null;
  onExpand: (panel: Exclude<ExpandedPanel, null>) => void;
}> = ({ result, baseDownloadName, staticInProgress = false, staticProgress = null, onExpand }) => {
  const staticReport = result?.report?.trim() ?? "";
  const vmReport = getDisplayVmReport(result?.vmReport);
  const dynamicPending = !!result?.dynamicPending;
  const staticPending = staticInProgress;
  const hasStatic = staticReport.length > 0;
  const hasVm = vmReport.length > 0;
  const showStaticSection = hasStatic || staticPending;
  const showVmSection = hasVm || dynamicPending;
  /** Metades fixas 50/50 quando há estático e VM (ou um deles ainda pendente). */
  const splitView = showStaticSection && showVmSection;

  const staticReportPanel = hasStatic ? (
    <CodePanel
      title="Relatório estático"
      language="report"
      code={staticReport}
      icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
      downloadFileName={buildShortFileName({
        baseName: baseDownloadName,
        kind: "report",
        parts: ["static"],
        ext: "txt",
        maxTotal: 120,
      })}
      onExpand={() => onExpand("report-static")}
    />
  ) : (
    <div className="h-full min-h-0 rounded-lg border border-border bg-card/30" aria-hidden />
  );

  if (splitView) {
    return (
      <div className="grid h-full min-h-0 grid-rows-2 gap-2 overflow-hidden">
        <StaticPanelShell
          loading={staticPending}
          progress={staticProgress}
          className="min-h-0 overflow-hidden"
          compactOverlay
        >
          <div className="flex h-full min-h-0 flex-col overflow-hidden">{staticReportPanel}</div>
        </StaticPanelShell>
        <div className="flex min-h-0 flex-col overflow-hidden border-t border-border/50 pt-2">
          {hasVm ? (
            <div className="flex h-full min-h-0 flex-col overflow-hidden">
              <CodePanel
                title="Relatório VM"
                language="report"
                code={vmReport}
                icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
                downloadFileName={buildShortFileName({
                  baseName: baseDownloadName,
                  kind: "report",
                  parts: ["vm"],
                  ext: "txt",
                  maxTotal: 120,
                })}
                onExpand={() => onExpand("report-vm")}
              />
            </div>
          ) : (
            <VmPendingPlaceholder />
          )}
        </div>
      </div>
    );
  }

  if (staticPending && !hasStatic && !hasVm) {
    return (
      <StaticPanelShell loading progress={staticProgress} className="h-full">
        <div className="h-full min-h-[120px] rounded-lg border border-border bg-card/30" aria-hidden />
      </StaticPanelShell>
    );
  }

  if (dynamicPending && !hasVm && !hasStatic) {
    return <VmPendingPlaceholder />;
  }

  const singleReport = hasVm ? vmReport : staticReport;
  const singleTitle = hasVm && !hasStatic ? "Relatório VM" : "Relatório";
  const singleExpandPanel: Exclude<ExpandedPanel, null> =
    hasVm && !hasStatic ? "report-vm" : "report-static";

  if (staticPending && !hasVm) {
    return (
      <StaticPanelShell loading progress={staticProgress} className="h-full">
        {singleReport ? (
          <CodePanel
            title={singleTitle}
            language="report"
            code={singleReport}
            icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
            onExpand={() => onExpand(singleExpandPanel)}
          />
        ) : (
          <div className="h-full min-h-[120px] rounded-lg border border-border bg-card/30" aria-hidden />
        )}
      </StaticPanelShell>
    );
  }

  return (
    <CodePanel
      title={singleTitle}
      language="report"
      code={singleReport}
      icon={<FileText className="h-3.5 w-3.5 text-code-string" />}
      downloadFileName={
        singleReport
          ? buildShortFileName({
              baseName: baseDownloadName,
              kind: "report",
              parts: hasVm && !hasStatic ? ["vm"] : [],
              ext: "txt",
              maxTotal: 120,
            })
          : undefined
      }
      onExpand={() => onExpand(singleExpandPanel)}
    />
  );
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
  geminiAllowMock = false,
  staticInProgress = false,
  staticProgress = null,
  onExpand,
}) => (
  <div className="grid grid-cols-1 gap-4 lg:grid-cols-3 min-h-0" style={{ height: "calc(100vh - 200px)" }}>
    <div className="flex min-h-0 flex-col">
      {flaggedFunctionsSorted.length > 0 && !staticInProgress && (
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
      <StaticPanelShell loading={staticInProgress} progress={staticProgress} className="flex-1">
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
          geminiAssist
          geminiAllowMock={geminiAllowMock}
          onExpand={() => onExpand("c")}
        />
      </StaticPanelShell>
    </div>
    <StaticPanelShell loading={staticInProgress} progress={staticProgress} className="min-h-0 h-full overflow-hidden">
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
    </StaticPanelShell>
    <div className="flex min-h-0 h-full flex-col overflow-hidden">
      <ReportColumn
        result={result}
        baseDownloadName={baseDownloadName}
        staticInProgress={staticInProgress}
        staticProgress={staticProgress}
        onExpand={onExpand}
      />
    </div>
  </div>
);

export default ResultsGrid;
