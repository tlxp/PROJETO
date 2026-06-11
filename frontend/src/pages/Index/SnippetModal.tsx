import React from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import type { SnippetPair } from "@/lib/analysis";

export type SnippetModalState = {
  open: boolean;
  title: string;
  pairs: SnippetPair[];
  currentIndex: number;
  fallbackContent?: string;
};

type SnippetModalProps = {
  state: SnippetModalState;
  onOpenChange: (open: boolean) => void;
  onNavigate: (delta: number) => void;
};

/** Modal "antes/depois da deobfuscação" com navegação entre casos. */
const SnippetModal: React.FC<SnippetModalProps> = ({ state, onOpenChange, onNavigate }) => (
  <Dialog open={state.open} onOpenChange={onOpenChange}>
    <DialogContent className="max-w-5xl max-h-[90vh] overflow-hidden flex flex-col">
      <DialogHeader>
        <DialogTitle className="font-mono text-sm">{state.title}</DialogTitle>
      </DialogHeader>
      {state.pairs.length > 0 ? (
        <>
          <div className="flex items-center justify-center gap-3 py-2 border-b border-border">
            <button
              type="button"
              onClick={() => onNavigate(-1)}
              className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground disabled:opacity-40"
              disabled={state.pairs.length <= 1}
              aria-label="Caso anterior"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <span className="text-xs font-mono text-muted-foreground min-w-[8rem] text-center">
              Caso {state.currentIndex + 1} de {state.pairs.length}
            </span>
            <button
              type="button"
              onClick={() => onNavigate(1)}
              className="rounded-lg border border-border bg-secondary p-2 text-muted-foreground transition-colors hover:bg-secondary/80 hover:text-foreground disabled:opacity-40"
              disabled={state.pairs.length <= 1}
              aria-label="Próximo caso"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>
          {state.pairs[state.currentIndex]?.description && (
            <p className="text-[11px] text-muted-foreground font-mono px-1">
              {state.pairs[state.currentIndex].description}
            </p>
          )}
          <div className="grid grid-cols-2 gap-3 flex-1 min-h-0 overflow-hidden">
            <div className="flex flex-col min-h-0 rounded border border-border bg-muted/20">
              <div className="px-2 py-1.5 border-b border-border text-[10px] font-mono uppercase tracking-wide text-muted-foreground">
                Antes (obfuscado)
              </div>
              <pre className="flex-1 overflow-auto p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
                {state.pairs[state.currentIndex]?.before || "—"}
              </pre>
            </div>
            <div className="flex flex-col min-h-0 rounded border border-border bg-muted/20">
              <div className="px-2 py-1.5 border-b border-border text-[10px] font-mono uppercase tracking-wide text-muted-foreground">
                Depois (deobfuscado)
              </div>
              <pre className="flex-1 overflow-auto p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
                {state.pairs[state.currentIndex]?.after || "—"}
              </pre>
            </div>
          </div>
        </>
      ) : (
        <pre className="flex-1 overflow-auto rounded border border-border bg-muted/30 p-3 text-[11px] font-mono whitespace-pre-wrap break-words">
          {state.fallbackContent ?? "—"}
        </pre>
      )}
    </DialogContent>
  </Dialog>
);

export default SnippetModal;
