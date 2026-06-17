import { AnimatePresence, motion } from "framer-motion";
import type { useIndexResultsViewModel } from "@/hooks/useIndexResultsViewModel";
import type { AnalysisResult, ReportCategory } from "@/lib/analysis";
import { isStaticAnalysisInProgress } from "@/lib/analysis";
import type { StillRunningJob } from "./UploadView";
import StillRunningNotice from "./StillRunningNotice";
import ResultsOverview from "./ResultsOverview";
import ResultsGrid from "./ResultsGrid";
import ExpandedView from "./ExpandedView";

export type IndexResultsViewModel = ReturnType<typeof useIndexResultsViewModel>;

export type AnalysisResultsViewProps = {
  resultsTitle: string;
  error: string | null;
  isAnalyzing: boolean;
  ghidraProgress: number | null;
  stillRunningJob: StillRunningJob | null;
  onClear: () => void;
  isMockDemo: boolean;
  result: AnalysisResult | null;
  currentJobId: string | null;
  reportCategories: ReportCategory[];
  reportResumoLines: string[] | null;
  overviewCategoryIndex: number;
  onChangeCategoryIndex: (updater: (prev: number) => number) => void;
  vm: IndexResultsViewModel;
};

const AnalysisResultsView = ({
  resultsTitle,
  error,
  isAnalyzing,
  ghidraProgress,
  stillRunningJob,
  onClear,
  isMockDemo,
  result,
  currentJobId,
  reportCategories,
  reportResumoLines,
  overviewCategoryIndex,
  onChangeCategoryIndex,
  vm,
}: AnalysisResultsViewProps) => {
  const staticInProgress = isStaticAnalysisInProgress(result, isAnalyzing);
  const staticProgress = staticInProgress
    ? (ghidraProgress ?? result?.staticProgress ?? null)
    : null;

  return (
  <motion.div key="results" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="space-y-4">
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-3">
        <h2 className="font-mono text-lg font-bold text-foreground break-all">{resultsTitle}</h2>
      </div>
      <button
        type="button"
        onClick={onClear}
        className="rounded-lg border border-border bg-secondary px-4 py-2 font-mono text-xs text-secondary-foreground transition-colors hover:bg-secondary/80"
      >
        Nova Análise
      </button>
    </div>

    {error && <p className="mt-2 text-sm text-destructive font-medium">{error}</p>}

    {stillRunningJob && (
      <StillRunningNotice jobId={stillRunningJob.jobId} lastStatus={stillRunningJob.lastStatus} />
    )}

    {result && (
      <ResultsOverview
        result={result}
        reportCategories={reportCategories}
        reportResumoLines={reportResumoLines}
        overviewCategoryIndex={overviewCategoryIndex}
        onChangeCategoryIndex={onChangeCategoryIndex}
        hasJobId={!!currentJobId}
      />
    )}

    <ResultsGrid
      result={result}
      flaggedFunctionsSorted={vm.flaggedFunctionsSorted}
      activeFlaggedFunctionIndex={vm.activeFlaggedFunctionIndex}
      activeFlaggedFunction={vm.activeFlaggedFunction}
      onSelectFlaggedFunction={(idx) => vm.selectFlaggedFunction(idx, { scroll: true })}
      scrollToLine={vm.scrollToLine}
      activeCDisplayRange={vm.activeCDisplayRange}
      highlightedLineRange={vm.highlightedLineRange}
      cFunctionHighlights={vm.cFunctionHighlights}
      baseDownloadName={vm.baseDownloadName}
      geminiAllowMock={isMockDemo}
      staticInProgress={staticInProgress}
      staticProgress={staticProgress}
      onExpand={vm.handleExpandPanel}
    />

    <AnimatePresence>
      {vm.expandedPanel && (
        <ExpandedView
          expandedPanel={vm.expandedPanel}
          result={result}
          baseDownloadName={vm.baseDownloadName}
          onClose={vm.handleCloseExpanded}
          onOpenSnippets={vm.handleOpenSnippets}
          flaggedFunctionsSorted={vm.flaggedFunctionsSorted}
          flaggedFunctionsOrder={vm.flaggedFunctionsOrder}
          onOrderChange={vm.setFlaggedFunctionsOrder}
          activeFlaggedFunctionIndex={vm.activeFlaggedFunctionIndex}
          activeCFunctionId={vm.activeCFunctionId}
          onSelectFlaggedFunction={vm.selectFlaggedFunction}
          onViewportLineChange={vm.handleViewportLineChange}
          reportChapters={vm.isReportExpanded ? vm.expandedReportChapters : vm.reportChapters}
          expandedReportText={vm.expandedReportText}
          expandedReportTitle={vm.expandedReportTitle}
          isReportExpanded={vm.isReportExpanded}
          scrollToLine={vm.scrollToLine}
          onScrollToLine={vm.setScrollToLine}
          highlightedLineRange={vm.highlightedLineRange}
          activeCDisplayRange={vm.activeCDisplayRange}
          cFunctionHighlights={vm.cFunctionHighlights}
          selectedWord={vm.selectedWord}
          onWordSelect={vm.handleWordSelect}
          onClearSelectedWord={vm.clearSelectedWord}
          wordStats={vm.wordStats}
          showReferences={vm.showReferences}
          referencesProgress={vm.referencesProgress}
          onOpenXrefExplorer={vm.openXrefExplorerFromSidebar}
          leftColWidth={vm.leftColWidth}
          rightColWidth={vm.rightColWidth}
          onLeftResizeStart={vm.handleLeftResizeStart}
          onRightResizeStart={vm.handleRightResizeStart}
          geminiAllowMock={isMockDemo}
        />
      )}
    </AnimatePresence>
  </motion.div>
  );
};

export default AnalysisResultsView;
