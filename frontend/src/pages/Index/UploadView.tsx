import React from "react";
import { motion } from "framer-motion";
import { Cpu } from "lucide-react";
import FileDropZone from "@/components/FileDropZone";
import type { AnalysisMode } from "@/lib/analysis";
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
  onResumeWaiting: () => void;
};

const MODES: { value: AnalysisMode; label: string }[] = [
  { value: "static", label: "Apenas estática" },
  { value: "dynamic", label: "Apenas dinâmica" },
  { value: "both", label: "Ambas" },
];

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
  onResumeWaiting,
}) => (
  <motion.div
    key="upload"
    initial={{ opacity: 0 }}
    animate={{ opacity: 1 }}
    exit={{ opacity: 0, y: -20 }}
    className="mx-auto max-w-xl space-y-6"
  >
    {/* Hero */}
    <div className="text-center space-y-2 pt-8 pb-4">
      <motion.h2
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        className="text-3xl font-bold tracking-tight text-foreground"
      >
        Analise o seu código
      </motion.h2>
      <p className="text-sm text-muted-foreground">
        Carregue um ficheiro .cs, .dll ou .exe para análise detalhada
      </p>
    </div>

    <FileDropZone onFileLoaded={onFileLoaded} currentFile={file} onClear={onClear} />

    {/* Seleção do tipo de análise */}
    <div className="mt-2 flex flex-wrap items-center justify-center gap-2 text-[11px] font-mono">
      <span className="text-muted-foreground">Tipo de análise:</span>
      {MODES.map((mode) => (
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
          {mode.label}
        </button>
      ))}
    </div>

    {error && (
      <p className="text-sm text-destructive font-medium text-center">{error}</p>
    )}

    {stillRunning && (
      <StillRunningNotice
        jobId={stillRunning.jobId}
        lastStatus={stillRunning.lastStatus}
        isWaiting={isAnalyzing}
        onResume={onResumeWaiting}
      />
    )}

    {analysisLogs.length > 0 && (
      <div className="mt-2 rounded-lg border border-border bg-card/70 px-3 py-2 font-mono text-[11px] text-muted-foreground max-h-52 overflow-auto">
        <div className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground/80">
          Logs de análise (desmontagem / descompilação)
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
          <span>Progresso Ghidra (pseudo-C)</span>
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

    {/* Actions */}
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
              A analisar...
            </>
          ) : (
            <>
              <Cpu className="h-4 w-4" />
              Executar Análise
            </>
          )}
        </button>
      </motion.div>
    )}

    {/* Botão de demo/mock para ver rapidamente o layout das 3 colunas */}
    <div className="pt-4 text-center">
      <button
        type="button"
        onClick={onLoadMock}
        className="text-[11px] font-mono text-muted-foreground underline underline-offset-4 hover:text-foreground"
      >
        Ver layout de teste (mock)
      </button>
    </div>
  </motion.div>
);

export default UploadView;
