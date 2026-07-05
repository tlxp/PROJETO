// --- Módulo: Index.tsx ---
// Página principal: upload e resultados de análise.

import { AnimatePresence } from "framer-motion";
import { useCallback } from "react";
import { useIndexAnalysisSession } from "@/hooks/useIndexAnalysisSession";
import { useIndexResultsViewModel } from "@/hooks/useIndexResultsViewModel";
import UploadView from "./Index/UploadView";
import IndexHeader from "./Index/IndexHeader";
import AnalysisResultsView from "./Index/AnalysisResultsView";
import SnippetModal from "./Index/SnippetModal";
import StubDriverConfirmDialog from "./Index/StubDriverConfirmDialog";

// --- Componente ---
const Index = () => {
  const session = useIndexAnalysisSession();
  const resultsVm = useIndexResultsViewModel({
    result: session.analysisResult,
    file: session.file,
    currentJobId: session.currentJobId,
  });

  const handleLoadMock = useCallback(() => {
    void session.loadMockDemo();
    resultsVm.resetViewState();
  }, [session, resultsVm]);

  const mockDemoUiEnabled =
    import.meta.env.DEV && import.meta.env.VITE_ENABLE_MOCK_DEMO === "true";

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
              mockDemoEnabled={mockDemoUiEnabled}
              stillRunning={session.stillRunningJob}
              showStubBanner={session.isStubDriver}
            />
          ) : (
            <AnalysisResultsView
              resultsTitle={resultsVm.resultsTitle}
              error={session.error}
              isAnalyzing={session.isAnalyzing}
              ghidraProgress={session.ghidraProgress}
              stillRunningJob={session.stillRunningJob}
              onClear={session.handleClear}
              isMockDemo={session.isMockDemo}
              result={session.analysisResult}
              currentJobId={session.currentJobId}
              reportCategories={resultsVm.reportCategories}
              reportResumoLines={resultsVm.reportResumoLines}
              overviewCategoryIndex={resultsVm.overviewCategoryIndex}
              onChangeCategoryIndex={resultsVm.setOverviewCategoryIndex}
              vm={resultsVm}
              showStubBanner={
                session.isStubDriver || !!session.analysisResult?.dynamicSimulated
              }
            />
          )}
        </AnimatePresence>

        <SnippetModal
          state={resultsVm.snippetModal}
          onOpenChange={(open) => resultsVm.setSnippetModal((s) => ({ ...s, open }))}
          onNavigate={resultsVm.navigateSnippet}
        />

        <StubDriverConfirmDialog
          open={session.stubConfirmOpen}
          onOpenChange={session.setStubConfirmOpen}
          onContinue={session.handleStubConfirmContinue}
          onStaticOnly={session.handleStubConfirmStaticOnly}
        />
      </main>
    </div>
  );
};

export default Index;
