// --- Módulo: CodePanelDownloadDialog.tsx ---
// Diálogo de opções de download.

import React from "react";

// --- Tipos ---
export type CodePanelDownloadDialogProps = {
  open: boolean;
  onClose: () => void;
  hasFlaggedFunctions: boolean;
  currentFlaggedRange: { start: number; end: number } | null;
  onDownloadFull: () => void;
  onDownloadCurrentFlagged: () => void;
  onDownloadAllFlagged: () => void;
};

// --- Componente ---
export const CodePanelDownloadDialog: React.FC<CodePanelDownloadDialogProps> = ({
  open,
  onClose,
  hasFlaggedFunctions,
  currentFlaggedRange,
  onDownloadFull,
  onDownloadCurrentFlagged,
  onDownloadAllFlagged,
}) => {
  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Opções de download"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="w-full max-w-md rounded-lg border border-border bg-card shadow-lg">
        <div className="border-b border-border px-4 py-3">
          <div className="font-mono text-xs font-semibold text-muted-foreground">Descarregar</div>
          <div className="mt-1 text-sm text-foreground">O que quer descarregar?</div>
        </div>
        <div className="space-y-2 px-4 py-3">
          <button
            type="button"
            onClick={onDownloadFull}
            className="w-full rounded-md border border-border bg-secondary/40 px-3 py-2 text-left text-[12px] text-foreground hover:bg-secondary/70 transition-colors"
          >
            Código todo
          </button>
          <button
            type="button"
            onClick={onDownloadCurrentFlagged}
            disabled={!hasFlaggedFunctions || !currentFlaggedRange}
            className={`w-full rounded-md border px-3 py-2 text-left text-[12px] transition-colors ${
              !hasFlaggedFunctions || !currentFlaggedRange
                ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
            }`}
            title={
              !hasFlaggedFunctions
                ? "Sem funções flagged"
                : !currentFlaggedRange
                  ? "Nenhuma função flagged ativa"
                  : "Descarregar apenas a função flagged atual"
            }
          >
            Função flagged atual
          </button>
          <button
            type="button"
            onClick={onDownloadAllFlagged}
            disabled={!hasFlaggedFunctions}
            className={`w-full rounded-md border px-3 py-2 text-left text-[12px] transition-colors ${
              !hasFlaggedFunctions
                ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
            }`}
            title={!hasFlaggedFunctions ? "Sem funções flagged" : "Descarregar todas as funções flagged"}
          >
            Todas as funções flagged
          </button>
        </div>
        <div className="flex items-center justify-end gap-2 border-t border-border px-4 py-3">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-border bg-card px-3 py-1.5 text-[12px] text-muted-foreground hover:bg-secondary/50 hover:text-foreground transition-colors"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>
  );
};
