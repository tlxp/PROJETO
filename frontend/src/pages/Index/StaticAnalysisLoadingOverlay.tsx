// --- Módulo: StaticAnalysisLoadingOverlay.tsx ---
// Overlay de progresso durante análise estática Ghidra.

import React from "react";
import { useI18n } from "@/i18n";

type StaticAnalysisLoadingOverlayProps = {
  progress: number | null;
  compact?: boolean;
};

// --- Componente ---
const StaticAnalysisLoadingOverlay: React.FC<StaticAnalysisLoadingOverlayProps> = ({
  progress,
  compact = false,
}) => {
  const { t } = useI18n();
  return (
    <div
      className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-2 rounded-lg bg-background/80 px-3 backdrop-blur-[2px]"
      aria-live="polite"
      aria-busy="true"
    >
      <p className={`font-mono font-medium text-muted-foreground ${compact ? "text-[10px]" : "text-xs"}`}>
        {t("staticLoading")}
      </p>
      <div className={compact ? "w-full max-w-[180px]" : "w-full max-w-[220px]"}>
        <div className="mb-1 flex items-center justify-between text-[10px] font-mono text-muted-foreground">
          <span>{progress != null ? t("staticGhidraProgress") : t("staticProcessing")}</span>
          <span>{progress != null ? `${progress.toFixed(1)}%` : "…"}</span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
          {progress != null ? (
            <div
              className="h-full rounded-full bg-primary transition-[width] duration-200"
              style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
            />
          ) : (
            <div className="relative h-full w-full overflow-hidden">
              <div className="absolute inset-y-0 w-2/5 animate-pulse rounded-full bg-primary/70" />
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

type StaticPanelShellProps = {
  loading: boolean;
  progress: number | null;
  children: React.ReactNode;
  className?: string;
  compactOverlay?: boolean;
};

export const StaticPanelShell: React.FC<StaticPanelShellProps> = ({
  loading,
  progress,
  children,
  className = "",
  compactOverlay = false,
}) => (
  <div className={`relative flex min-h-0 flex-col overflow-hidden ${className}`}>
    <div
      className={`flex min-h-0 flex-1 flex-col transition-opacity duration-200 ${
        loading ? "pointer-events-none opacity-35" : ""
      }`}
    >
      {children}
    </div>
    {loading ? <StaticAnalysisLoadingOverlay progress={progress} compact={compactOverlay} /> : null}
  </div>
);

export default StaticAnalysisLoadingOverlay;
