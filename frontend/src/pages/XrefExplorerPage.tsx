import React, { useCallback, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowDown, Code2, GitBranch, Terminal } from "lucide-react";
import CodePanel from "@/components/CodePanel";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  buildXrefViewModel,
  openXrefExplorerTab,
  readXrefSession,
  writeXrefSession,
  type XrefSessionPayload,
} from "@/lib/cCodeXref";
import { buildShortFileName } from "@/lib/artifactNaming";

function snippetAroundLine(code: string, line: number, context = 3): string {
  const lines = code.split("\n");
  const i = Math.max(0, Math.min(lines.length - 1, line - 1));
  const from = Math.max(0, i - context);
  const to = Math.min(lines.length, i + context + 1);
  return lines
    .slice(from, to)
    .map((l, j) => `${String(from + j + 1).padStart(5, " ")} | ${l}`)
    .join("\n");
}

function downloadTextFile(text: string, fileName: string): void {
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = fileName;
  a.click();
  URL.revokeObjectURL(a.href);
}

const XrefExplorerPage: React.FC = () => {
  const [payload] = useState<XrefSessionPayload | null>(() => readXrefSession());
  const [scrollToLine, setScrollToLine] = useState<number | null>(null);
  const [focusLine, setFocusLine] = useState<number | null>(null);
  const [mentionWheelIdx, setMentionWheelIdx] = useState<number>(0);
  const [exportOpen, setExportOpen] = useState(false);
  const wheelAccumRef = useRef(0);
  const lastWheelAtRef = useRef(0);
  const lastWheelStepAtRef = useRef(0);

  const model = useMemo(() => {
    if (!payload?.code || !payload.word) return null;
    return buildXrefViewModel(payload.code, payload.word);
  }, [payload?.code, payload?.word]);

  const functionRangesForXrefs = useMemo(() => {
    if (!model) return null;
    const ranges = model.orderedNodes
      .map((n) => ({ start: n.startLine, end: n.endLine }))
      .filter((r) => Number.isFinite(r.start) && Number.isFinite(r.end) && r.start >= 1 && r.end >= r.start)
      .sort((a, b) => a.start - b.start || a.end - b.end);
    // Dedup simples (ranges iguais)
    const out: { start: number; end: number }[] = [];
    for (const r of ranges) {
      const prev = out[out.length - 1];
      if (prev && prev.start === r.start && prev.end === r.end) continue;
      out.push(r);
    }
    return out.length ? out : null;
  }, [model]);

  const allMentionLines = useMemo(() => {
    if (!model) return [] as number[];
    const s = new Set<number>();
    for (const n of model.orderedNodes) for (const ln of n.mentionLines) s.add(ln);
    return [...s].sort((a, b) => a - b);
  }, [model]);

  const activeMentionLine = allMentionLines.length ? allMentionLines[mentionWheelIdx] ?? null : null;
  const activeNode = useMemo(() => {
    if (!model || activeMentionLine == null) return null;
    return model.orderedNodes.find((n) => n.mentionLines.includes(activeMentionLine)) ?? null;
  }, [activeMentionLine, model]);

  const initialFocusLine = useMemo(() => {
    if (!model) return null;
    const origin = model.origin;
    if (origin && origin.mentionLines.length) return Math.min(...origin.mentionLines);
    const first = model.orderedNodes[0];
    if (first && first.mentionLines.length) return Math.min(...first.mentionLines);
    return null;
  }, [model]);

  // Garantir que o painel abre já focado no símbolo.
  React.useEffect(() => {
    if (focusLine == null && initialFocusLine != null) setFocusLine(initialFocusLine);
  }, [focusLine, initialFocusLine]);

  // Sincronizar o índice do wheel com a linha atual (quando existe).
  React.useEffect(() => {
    if (!allMentionLines.length) return;
    const ln = focusLine ?? scrollToLine ?? initialFocusLine;
    if (ln == null) return;
    const idx = allMentionLines.indexOf(ln);
    if (idx >= 0) setMentionWheelIdx(idx);
  }, [allMentionLines, focusLine, initialFocusLine, scrollToLine]);

  const goToMentionIdx = useCallback(
    (idx: number) => {
      if (!allMentionLines.length) return;
      const clamped = ((idx % allMentionLines.length) + allMentionLines.length) % allMentionLines.length;
      const ln = allMentionLines[clamped];
      if (!ln) return;
      setMentionWheelIdx(clamped);
      setFocusLine(ln);
      setScrollToLine(ln);
      setTimeout(() => setScrollToLine(null), 1200);
    },
    [allMentionLines]
  );

  const handleMentionsWheel = useCallback(
    (e: React.WheelEvent<HTMLElement>) => {
      if (!allMentionLines.length) return;
      const dy = e.deltaY;
      if (dy === 0) return;
      e.preventDefault();
      // Muitos devices disparam vários eventos por "tick"/notch.
      // Fazemos acumulação + threshold para garantir no máximo 1 passo por notch.
      const now = performance.now();
      // Rate-limit: nunca mais do que 1 passo a cada 90ms
      if (now - lastWheelStepAtRef.current < 90) return;
      if (now - lastWheelAtRef.current > 180) {
        wheelAccumRef.current = 0;
      }
      lastWheelAtRef.current = now;

      // Normalizar por deltaMode: 0=pixels, 1=lines, 2=pages
      const mode = (e.deltaMode ?? 0) as number;
      const dyPx =
        mode === 1 ? dy * 16 : mode === 2 ? dy * 400 : dy; // aproximações razoáveis

      const threshold = 120; // ~1 notch típico
      // Se vier um delta gigante num único evento, ainda assim: só 1 passo.
      if (Math.abs(dyPx) >= threshold) {
        wheelAccumRef.current = 0;
        lastWheelStepAtRef.current = now;
        goToMentionIdx(mentionWheelIdx + (dyPx > 0 ? 1 : -1));
        return;
      }

      wheelAccumRef.current += dyPx;
      if (wheelAccumRef.current >= threshold) {
        wheelAccumRef.current = 0;
        lastWheelStepAtRef.current = now;
        goToMentionIdx(mentionWheelIdx + 1);
      } else if (wheelAccumRef.current <= -threshold) {
        wheelAccumRef.current = 0;
        lastWheelStepAtRef.current = now;
        goToMentionIdx(mentionWheelIdx - 1);
      }
    },
    [allMentionLines.length, goToMentionIdx, mentionWheelIdx]
  );

  const nameById = useMemo(() => {
    const m = new Map<string, string>();
    if (!model) return m;
    for (const n of model.orderedNodes) m.set(n.id, n.name);
    return m;
  }, [model]);

  const handleWordSelect = useCallback(
    (word: string) => {
      const w = word.trim();
      if (w.length < 2 || !payload) return;
      writeXrefSession({
        v: 1,
        code: payload.code,
        word: w,
        fileName: payload.fileName,
        flaggedIndicators: payload.flaggedIndicators,
      });
      openXrefExplorerTab();
    },
    [payload]
  );

  const baseName = (payload?.fileName ?? "output").replace(/\.[^.]+$/, "") || "output";
  const exportBaseName = buildShortFileName({
    baseName,
    kind: "xrefs",
    parts: [payload?.word ?? "symbol"],
    ext: "txt",
    maxTotal: 90,
  }).replace(/\.txt$/i, "");

  if (!payload) {
    return (
      <div className="h-[100dvh] overflow-hidden bg-background grid-bg">
        <header className="border-b border-border bg-card/80 backdrop-blur-sm">
          <div className="container flex items-center gap-3 py-4">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 glow-primary">
              <Terminal className="h-5 w-5 text-primary" />
            </div>
            <div>
              <h1 className="font-mono text-lg font-bold text-foreground tracking-tight">CodeAnalyzer</h1>
              <p className="text-[11px] text-muted-foreground">Xrefs</p>
            </div>
          </div>
        </header>
        <main className="container py-12 max-w-lg space-y-4">
          <p className="text-sm text-muted-foreground">
            Não há dados de análise neste separador. Abra os xrefs a partir do pseudo-C (duplo-clique num símbolo e clique no número de menções na barra lateral).
          </p>
          <Link to="/" className="inline-flex text-sm font-medium text-primary hover:underline">
            Voltar ao início
          </Link>
        </main>
      </div>
    );
  }

  return (
    <div className="h-[100dvh] overflow-hidden bg-background grid-bg flex flex-col">
      <header className="border-b border-border bg-card/80 backdrop-blur-sm shrink-0">
        <div className="container flex flex-wrap items-center justify-between gap-3 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 glow-primary">
              <Terminal className="h-5 w-5 text-primary" />
            </div>
            <div>
              <h1 className="font-mono text-lg font-bold text-foreground tracking-tight">CodeAnalyzer</h1>
              <p className="text-[11px] text-muted-foreground">Mapa de xrefs (pseudo-C)</p>
            </div>
          </div>
          <Link
            to="/"
            className="text-xs font-mono text-muted-foreground hover:text-primary transition-colors border border-border rounded-md px-3 py-1.5 bg-card/60"
          >
            Voltar à análise
          </Link>
        </div>
      </header>

      <main className="container flex-1 flex flex-col py-6 gap-4 min-h-0 overflow-hidden">
        <div className="flex flex-wrap items-baseline gap-2 border-b border-border pb-3">
          <GitBranch className="h-4 w-4 text-primary shrink-0" />
          <h2 className="font-mono text-sm font-semibold text-foreground">Xrefs para</h2>
          <span className="font-mono text-sm text-accent break-all">{payload.word}</span>
          <span className="text-[11px] text-muted-foreground">· {payload.fileName}</span>
          <div className="flex-1" />
          <button
            type="button"
            onClick={() => setExportOpen(true)}
            className="text-xs font-mono text-muted-foreground hover:text-primary transition-colors border border-border rounded-md px-3 py-1.5 bg-card/60"
          >
            Transferir
          </button>
        </div>

        <div className="grid flex-1 min-h-0 overflow-hidden grid-cols-1 lg:grid-cols-[minmax(280px,380px)_1fr] gap-4">
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-col min-h-0 rounded-lg border border-border bg-card/40 overflow-hidden"
          >
            <div className="shrink-0 border-b border-border px-3 py-2 flex items-center gap-2">
              <span className="text-[10px] font-mono uppercase tracking-wide text-muted-foreground">Fluxo (IDA)</span>
            </div>
            <div className="flex-1 min-h-0 overflow-auto px-3 pt-3 pb-3 space-y-0">
              {!model || model.orderedNodes.length === 0 ? (
                <p className="text-xs text-muted-foreground">Sem funções com este símbolo.</p>
              ) : (
                model.orderedNodes.map((node, idx) => {
                  // Para "Origem", queremos mostrar a linha real de definição/assinatura do símbolo,
                  // e não a primeira menção dentro do corpo.
                  const previewLine =
                    node.isOrigin && node.originDeclLine != null
                      ? node.originDeclLine
                      : node.mentionLines.length
                        ? Math.min(...node.mentionLines)
                        : node.startLine;
                  const openFunctionStartLine =
                    node.isOrigin && node.originDeclLine != null ? node.originDeclLine : node.startLine;
                  const callees = model.edges
                    .filter((e) => e.fromId === node.id)
                    .map((e) => nameById.get(e.toId) ?? e.toId);
                  const showArrow = idx < model.orderedNodes.length - 1;
                  return (
                    <div key={node.id}>
                      <div
                        className={`rounded-md border px-2 py-2 font-mono text-[11px] ${
                          node.isOrigin
                            ? "border-primary/60 bg-primary/10"
                            : "border-border/60 bg-muted/20"
                        } cursor-pointer hover:border-primary/40 hover:bg-primary/5 transition-colors`}
                        role="button"
                        tabIndex={0}
                        onClick={() => {
                          setFocusLine(openFunctionStartLine);
                          setScrollToLine(openFunctionStartLine);
                          setTimeout(() => setScrollToLine(null), 1200);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === "Enter" || e.key === " ") {
                            e.preventDefault();
                            setFocusLine(openFunctionStartLine);
                            setScrollToLine(openFunctionStartLine);
                            setTimeout(() => setScrollToLine(null), 1200);
                          }
                        }}
                      >
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <span className="font-semibold text-foreground truncate">{node.name}</span>
                          {node.isOrigin && (
                            <span className="shrink-0 text-[9px] uppercase tracking-wide text-primary">Origem</span>
                          )}
                        </div>
                        <div className="text-muted-foreground text-[10px] mb-1.5">
                          L{node.startLine}–L{node.endLine} · {node.mentionLines.length} menção
                          {node.mentionLines.length !== 1 ? "ões" : ""}
                        </div>
                        {callees.length > 0 && (
                          <div className="text-[10px] text-muted-foreground mb-1.5">
                            Chama: <span className="text-foreground">{callees.join(", ")}</span>
                          </div>
                        )}
                        <pre className="mt-1 max-h-28 overflow-auto rounded bg-code-bg/80 p-2 text-[10px] leading-snug text-foreground/90 whitespace-pre border border-border/40">
                          {snippetAroundLine(payload.code, previewLine, 2)}
                        </pre>
                        <div
                          className="mt-1.5 flex flex-wrap gap-1 max-h-16 overflow-auto"
                          title="Scroll para ver mais menções"
                          onClick={(e) => e.stopPropagation()}
                        >
                          {node.mentionLines.map((ln) => (
                            <button
                              key={ln}
                              type="button"
                              onClick={() => {
                                const idx = allMentionLines.indexOf(ln);
                                if (idx >= 0) goToMentionIdx(idx);
                                else {
                                  setFocusLine(ln);
                                  setScrollToLine(ln);
                                  setTimeout(() => setScrollToLine(null), 1200);
                                }
                              }}
                              className="rounded px-1.5 py-0.5 text-[10px] bg-secondary/80 text-foreground hover:bg-primary/20 hover:text-primary transition-colors"
                            >
                              L{ln}
                            </button>
                          ))}
                        </div>
                      </div>
                      {showArrow && (
                        <div className="flex justify-center py-1 text-primary/70">
                          <ArrowDown className="h-4 w-4" aria-hidden />
                        </div>
                      )}
                    </div>
                  );
                })
              )}
              {model && model.edges.length > 0 && (
                <div className="mt-4 pt-3 border-t border-border text-[10px] text-muted-foreground font-mono space-y-1">
                  <div className="text-[9px] uppercase tracking-wide mb-1">Arestas (chamadas)</div>
                  {model.edges.map((e) => (
                    <div key={`${e.fromId}-${e.toId}`}>
                      {nameById.get(e.fromId) ?? e.fromId} → {nameById.get(e.toId) ?? e.toId}
                    </div>
                  ))}
                </div>
              )}
            </div>

          </motion.div>

          <div className="flex flex-col min-h-0 min-h-[420px] lg:min-h-0 rounded-lg border border-border overflow-hidden bg-card/30">
            <div className="shrink-0 border-b border-border px-3 py-2">
              <p className="text-[10px] font-mono text-muted-foreground">
                Duplo-clique num identificador para abrir outro mapa de xrefs num novo separador.
              </p>
            </div>
            <div className="flex-1 min-h-0 overflow-hidden">
              <CodePanel
                title="Pseudo-C"
                language="C"
                code={payload.code}
                icon={<Code2 className="h-3.5 w-3.5 text-primary" />}
                embedded
                compactHeader
                scrollToLine={scrollToLine}
                displayLineRanges={functionRangesForXrefs}
                showDisplayRangesNotice={false}
                selectedWord={payload.word}
                onWordSelect={handleWordSelect}
                flaggedIndicators={payload.flaggedIndicators ?? undefined}
                downloadFileName={null}
                hideLimitNotice
              />
            </div>
          </div>
        </div>
      </main>

      <Dialog open={exportOpen} onOpenChange={setExportOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="font-mono text-sm">Transferir xrefs</DialogTitle>
          </DialogHeader>

          <div className="space-y-3">
            <div className="rounded-md border border-border bg-card/60 p-3 text-[12px]">
              <div className="font-mono text-[11px] text-muted-foreground">Símbolo</div>
              <div className="font-mono text-foreground break-all">{payload.word}</div>
              <div className="mt-1 font-mono text-[11px] text-muted-foreground">
                {activeNode?.name ? `Função: ${activeNode.name}` : ""}
              </div>
            </div>

            <div className="grid grid-cols-1 gap-2">
              <button
                type="button"
                disabled={!payload.code || !activeNode}
                onClick={() => {
                  if (!payload.code || !activeNode) return;
                  const lines = payload.code.split("\n");
                  const chunk = lines.slice(activeNode.startLine - 1, activeNode.endLine).join("\n");
                  const header = `// Xrefs para: ${payload.word}\n// Função: ${activeNode.name}\n// Linhas: ${activeNode.startLine}-${activeNode.endLine}\n\n`;
                  const fileName = buildShortFileName({
                    baseName,
                    kind: "xrefs_fn",
                    parts: [payload?.word ?? "symbol", activeNode.name || "current"],
                    ext: "c",
                    maxTotal: 120,
                  });
                  downloadTextFile(header + chunk, fileName);
                  setExportOpen(false);
                }}
                className={`w-full rounded-md border px-3 py-2 text-left transition-colors ${
                  !payload.code || !activeNode
                    ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                    : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
                }`}
              >
                <div className="font-mono text-[12px]">Apenas a função atual</div>
                <div className="mt-0.5 text-[11px] text-muted-foreground">
                  Exporta só a função onde está a menção selecionada.
                </div>
              </button>

              <button
                type="button"
                disabled={!payload.code || !model || model.orderedNodes.length === 0}
                onClick={() => {
                  if (!payload.code || !model) return;
                  const lines = payload.code.split("\n");
                  const parts = model.orderedNodes
                    .filter((n) => n.mentionLines.length > 0)
                    .map((n) => {
                      const chunk = lines.slice(n.startLine - 1, n.endLine).join("\n");
                      return `// ---\n// Função: ${n.name}\n// Linhas: ${n.startLine}-${n.endLine}\n// Menções: ${n.mentionLines.map((x) => `L${x}`).join(", ")}\n\n${chunk}\n`;
                    });
                  const header = `// Xrefs para: ${payload.word}\n// Total de funções com menção: ${parts.length}\n\n`;
                  const fileName = buildShortFileName({
                    baseName,
                    kind: "xrefs_all",
                    parts: [payload?.word ?? "symbol"],
                    ext: "c",
                    maxTotal: 120,
                  });
                  downloadTextFile(header + parts.join("\n"), fileName);
                  setExportOpen(false);
                }}
                className={`w-full rounded-md border px-3 py-2 text-left transition-colors ${
                  !payload.code || !model || model.orderedNodes.length === 0
                    ? "border-border/60 bg-muted/40 text-muted-foreground cursor-not-allowed"
                    : "border-border bg-secondary/40 text-foreground hover:bg-secondary/70"
                }`}
              >
                <div className="font-mono text-[12px]">Todas as funções com a menção</div>
                <div className="mt-0.5 text-[11px] text-muted-foreground">
                  Exporta todas as funções que referenciam o símbolo.
                </div>
              </button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default XrefExplorerPage;
