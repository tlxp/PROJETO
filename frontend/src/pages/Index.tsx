import { AnimatePresence } from "framer-motion";
import { useCallback } from "react";
import { useIndexAnalysisSession } from "@/hooks/useIndexAnalysisSession";
import { useIndexResultsViewModel } from "@/hooks/useIndexResultsViewModel";
import UploadView from "./Index/UploadView";
import IndexHeader from "./Index/IndexHeader";
import AnalysisResultsView from "./Index/AnalysisResultsView";
import SnippetModal from "./Index/SnippetModal";

const Index = () => {
  const session = useIndexAnalysisSession();
  const resultsVm = useIndexResultsViewModel({
    result: session.analysisResult,
    file: session.file,
    currentJobId: session.currentJobId,
  });

  const handleLoadMock = useCallback(() => {
    session.loadMockDemo();
    resultsVm.resetViewState();
  }, [session, resultsVm]);

  return (
    <div className="min-h-screen bg-background grid-bg">
      <IndexHeader />

      <main className="container py-8">
        <AnimatePresence mode="wait">
          {!session.showResults ? (
            <UploadView
              key="upload"
              file={session.file}
              onFileLoaded={session.handleFileLoaded}
              onClear={session.handleClear}
              analysisMode={session.analysisMode}
              onModeChange={session.setAnalysisMode}
              error={session.error}
              analysisLogs={session.analysisLogs}
              ghidraProgress={session.ghidraProgress}
              isAnalyzing={session.isAnalyzing}
              onAnalyze={session.handleAnalyze}
              onLoadMock={handleLoadMock}
              stillRunning={session.stillRunningJob}
              onResumeWaiting={session.handleResumeWaiting}
            />
          ) : (
            <AnalysisResultsView
              resultsTitle={resultsVm.resultsTitle}
              error={session.error}
              isAnalyzing={session.isAnalyzing}
              stillRunningJob={session.stillRunningJob}
              onClear={session.handleClear}
              onResumeWaiting={session.handleResumeWaiting}
              result={session.analysisResult}
              currentJobId={session.currentJobId}
              reportCategories={resultsVm.reportCategories}
              reportResumoLines={resultsVm.reportResumoLines}
              overviewCategoryIndex={resultsVm.overviewCategoryIndex}
              onChangeCategoryIndex={resultsVm.setOverviewCategoryIndex}
              vm={resultsVm}
            />
          )}
        </AnimatePresence>

        <SnippetModal
          state={resultsVm.snippetModal}
          onOpenChange={(open) => resultsVm.setSnippetModal((s) => ({ ...s, open }))}
          onNavigate={resultsVm.navigateSnippet}
        />
      </main>
    </div>
  );
};

export default Index;
