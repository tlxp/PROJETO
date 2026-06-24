// --- Módulo: UploadView.tsx ---
import React from "react";
import { motion } from "framer-motion";
import { Cpu } from "lucide-react";
import FileDropZone from "@/components/FileDropZone";
import type { AnalysisMode } from "@/lib/analysis";
import { useI18n } from "@/i18n";
import StillRunningNotice from "./StillRunningNotice";

export type StillRunningJob = { jobId: string; lastStatus: string };

type UploadViewProps = {
  file: File | null;
  onFileLoaded: (file: File) => void;
  onClear: () => void;
  analysisMode: AnalysisMode;
  onModeChange: (mode: AnalysisMode) => void;
  error: string | null;
  analysisLogs: string[];
  ghidraProgress: number | null;
  isAnalyzing: boolean;
  onAnalyze: () => void;
  onLoadMock: () => void;
  stillRunning: StillRunningJob | null;
};

// --- Vista de upload: drop zone, modo de análise e logs ---
const UploadView: React.FC<UploadViewProps> = ({
  file,
  onFileLoaded,
  onClear,
  analysisMode,
  onModeChange,
  error,
  analysisLogs,
  ghidraProgress,
  isAnalyzing,
  onAnalyze,
  onLoadMock,
  stillRunning,
}) => {
  const { t } = useI18n();
  const modes: { value: AnalysisMode; labelKey: "modeStatic" | "modeDynamic" | "modeBoth" }[] = [
    { value: "static", labelKey: "modeStatic" },
    { value: "dynamic", labelKey: "modeDynamic" },
    { value: "both", labelKey: "modeBoth" },
  ];

  return (
    <motion.div
      key="upload"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0, y: -20 }}
      className="mx-auto max-w-xl space-y-6"
    >
      <div className="text-center space-y-2 pt-8 pb-4">
        <motion.h2
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-3xl font-bold tracking-tight text-foreground"
        >
          {t("heroTitle")}
        </motion.h2>
        <p className="text-sm text-muted-foreground">{t("heroSubtitle")}</p>
      </div>

      <FileDropZone onFileLoaded={onFileLoaded} currentFile={file} onClear={onClear} />

      <div className="mt-2 flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono">
        <span className="text-muted-foreground">{t("analysisType")}</span>
        {modes.map((mode) => (
          <button
            key={mode.value}
            type="button"
            onClick={() => onModeChange(mode.value)}
            className={`rounded-full px-3 py-1 border text-xs transition-colors ${
              analysisMode === mode.value
                ? "border-primary bg-primary/10 text-primary"
                : "border-border bg-card text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
            }`}
          >
            {t(mode.labelKey)}
          </button>
        ))}
      </div>

      {error && <p className="text-sm text-destructive font-medium text-center">{error}</p>}

      {stillRunning && (
        <StillRunningNotice jobId={stillRunning.jobId} lastStatus={stillRunning.lastStatus} />
      )}

      {analysisLogs.length > 0 && (
        <div className="mt-2 rounded-lg border border-border bg-card/70 px-3 py-2 font-mono text-[11px] text-muted-foreground max-h-52 overflow-auto">
          <div className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground/80">
            {t("analysisLogsTitle")}
          </div>
          {analysisLogs.map((line, idx) => (
            <div key={idx} className="whitespace-pre-wrap">
              {line}
            </div>
          ))}
        </div>
      )}

      {ghidraProgress != null && (
        <div className="mt-2 rounded-lg border border-border bg-card/70 px-3 py-2">
          <div className="mb-1 flex items-center justify-between text-[11px] font-mono text-muted-foreground">
            <span>{t("ghidraProgress")}</span>
            <span>{ghidraProgress.toFixed(1)}%</span>
          </div>
          <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
            <div
              className="h-full bg-primary transition-[width] duration-200"
              style={{ width: `${ghidraProgress}%` }}
            />
          </div>
        </div>
      )}

      {file && (
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex gap-3"
        >
          <button
            onClick={onAnalyze}
            disabled={isAnalyzing}
            className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-primary px-4 py-3 font-mono text-sm font-semibold text-primary-foreground transition-all hover:brightness-110 glow-primary disabled:opacity-50"
          >
            {isAnalyzing ? (
              <>
                <Cpu className="h-4 w-4 animate-spin" />
                {t("analyzing")}
              </>
            ) : (
              <>
                <Cpu className="h-4 w-4" />
                {t("analyze")}
              </>
            )}
          </button>
        </motion.div>
      )}

      <div className="pt-4 text-center">
        <button
          type="button"
          onClick={onLoadMock}
          className="text-[11px] font-mono text-muted-foreground underline underline-offset-4 hover:text-foreground"
        >
          {t("mockLayout")}
        </button>
      </div>
    </motion.div>
  );
};

export default UploadView;
