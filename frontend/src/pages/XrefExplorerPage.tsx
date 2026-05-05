import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useLocation, useParams } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowDown, Code2, GitBranch, Terminal } from "lucide-react";
import CodePanel from "@/components/CodePanel";
import {
  buildXrefViewModel,
  openXrefExplorerTab,
  readXrefSession,
  writeXrefSession,
  type XrefSessionPayload,
} from "@/lib/cCodeXref";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";
const MENTION_CONTEXT_LINES = 50;
const MENTION_CHUNK_LINES = 1;
const MENTION_WINDOW_MAX_LINES = 1200;
const DEFAULT_MENTIONS_TO_SHOW = 10;

function formatMentions(n: number): string {
  if (n === 1) return "1 menção";
  return `${n.toLocaleString()} menções`;
}

type MentionGroup = { start: number; end: number; lines: number[] };
function groupMentionLines(lines: number[]): MentionGroup[] {
  const sorted = [...lines].filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  const out: MentionGroup[] = [];
  let cur: MentionGroup | null = null;
  for (const ln of sorted) {
    if (!cur) {
      cur = { start: ln, end: ln, lines: [ln] };
      continue;
    }
    if (ln === cur.end + 1) {
      cur.end = ln;
      cur.lines.push(ln);
      continue;
    }
    out.push(cur);
    cur = { start: ln, end: ln, lines: [ln] };
  }
  if (cur) out.push(cur);
  return out;
}

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

const XrefExplorerPage: React.FC = () => {
  const location = useLocation();
  const { jobId } = useParams<{ jobId?: string }>();
  const [payload, setPayload] = useState<XrefSessionPayload | null>(() => readXrefSession());
  const [scrollToLine, setScrollToLine] = useState<number | null>(null);
  const [windowFocusLine, setWindowFocusLine] = useState<number | null>(null);
  const [expandedMentionsByNode, setExpandedMentionsByNode] = useState<Record<string, boolean>>({});

  const wordFromQuery = useMemo(() => {
    const params = new URLSearchParams(location.search ?? "");
    const w = params.get("word");
    return typeof w === "string" ? w.trim() : "";
  }, [location.search]);

  useEffect(() => {
    // Se existe jobId no URL, carregamos o pseudo-C do backend e ignoramos a sessão local.
    if (!jobId) return;
    if (!wordFromQuery) return;
    let cancelled = false;

    const run = async () => {
      try {
        const res = await fetch(`${API_BASE}/api/analysis/${encodeURIComponent(jobId)}`);
        if (!res.ok) {
          if (!cancelled) setPayload(null);
          return;
        }
        const job = (await res.json()) as unknown;
        const rec = (job && typeof job === "object" ? (job as Record<string, unknown>) : null) ?? {};

        // Backends diferentes: alguns devolvem cCode no topo, outros dentro de staticResult.
        const staticResult =
          rec.staticResult && typeof rec.staticResult === "object"
            ? (rec.staticResult as Record<string, unknown>)
            : null;

        const cCode =
          typeof rec.cCode === "string"
            ? rec.cCode
            : typeof staticResult?.cCode === "string"
              ? (staticResult.cCode as string)
              : "";

        const fileName =
          typeof rec.fileName === "string"
            ? rec.fileName
            : typeof staticResult?.fileName === "string"
              ? (staticResult.fileName as string)
              : "output";

        const flaggedIndicatorsRaw =
          Array.isArray(rec.flaggedIndicators) ? rec.flaggedIndicators : Array.isArray(staticResult?.flaggedIndicators) ? staticResult?.flaggedIndicators : [];
        const flaggedIndicators = (flaggedIndicatorsRaw as unknown[]).filter(
          (x): x is string => typeof x === "string"
        );

        if (!cancelled) {
          setPayload({
            v: 1,
            code: cCode,
            word: wordFromQuery,
            fileName,
            flaggedIndicators,
          });
        }
      } catch {
        if (!cancelled) setPayload(null);
      }
    };

    void run();
    return () => {
      cancelled = true;
    };
  }, [jobId, wordFromQuery]);

  const model = useMemo(() => {
    if (!payload?.code || !payload.word) return null;
    return buildXrefViewModel(payload.code, payload.word);
  }, [payload?.code, payload?.word]);

  // Ao abrir a página, focar automaticamente a primeira menção (origem) em modo janela,
  // para evitar renderizar as primeiras 4000 linhas do ficheiro.
  useEffect(() => {
    if (!model || model.orderedNodes.length === 0) return;
    if (windowFocusLine != null) return; // não sobrescrever foco do utilizador
    const origin = model.orderedNodes.find((n) => n.isOrigin) ?? model.orderedNodes[0];
    const ln = origin ? Math.min(...origin.mentionLines) : null;
    if (ln != null && Number.isFinite(ln)) {
      setWindowFocusLine(ln);
      setScrollToLine(ln);
      setTimeout(() => setScrollToLine(null), 1200);
    }
  }, [model, windowFocusLine]);

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
      setWindowFocusLine(null);
      // Preferir URL com jobId (permalink) quando disponível
      if (jobId) {
        openXrefExplorerTab(`/analysis/${encodeURIComponent(jobId)}/xref?word=${encodeURIComponent(w)}`);
        return;
      }

      writeXrefSession({
        v: 1,
        code: payload.code,
        word: w,
        fileName: payload.fileName,
        flaggedIndicators: payload.flaggedIndicators,
      });
      openXrefExplorerTab("/xref");
    },
    [payload, jobId]
  );

  const baseName = (payload?.fileName ?? "output").replace(/\.[^.]+$/, "") || "output";

  if (!payload) {
    return (
      <div className="min-h-screen bg-background grid-bg">
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
          <Link
            to={jobId ? `/analysis/${encodeURIComponent(jobId)}` : "/"}
            className="inline-flex text-sm font-medium text-primary hover:underline"
          >
            Voltar ao início
          </Link>
        </main>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background grid-bg flex flex-col">
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
            to={jobId ? `/analysis/${encodeURIComponent(jobId)}` : "/"}
            className="text-xs font-mono text-muted-foreground hover:text-primary transition-colors border border-border rounded-md px-3 py-1.5 bg-card/60"
          >
            Voltar à análise
          </Link>
        </div>
      </header>

      <main className="container flex-1 flex flex-col py-6 gap-4 min-h-0">
        <div className="flex flex-wrap items-baseline gap-2 border-b border-border pb-3">
          <GitBranch className="h-4 w-4 text-primary shrink-0" />
          <h2 className="font-mono text-sm font-semibold text-foreground">Xrefs para</h2>
          <span className="font-mono text-sm text-accent break-all">{payload.word}</span>
          <span className="text-[11px] text-muted-foreground">· {payload.fileName}</span>
        </div>

        <div className="grid flex-1 min-h-0 grid-cols-1 lg:grid-cols-[minmax(280px,380px)_1fr] gap-4">
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-col min-h-0 rounded-lg border border-border bg-card/40 overflow-hidden"
          >
            <div className="shrink-0 border-b border-border px-3 py-2 flex items-center gap-2">
              <span className="text-[10px] font-mono uppercase tracking-wide text-muted-foreground">Fluxo (IDA)</span>
            </div>
            <div className="flex-1 overflow-auto p-3 space-y-0">
              {!model || model.orderedNodes.length === 0 ? (
                <p className="text-xs text-muted-foreground">Sem funções com este símbolo.</p>
              ) : (
                model.orderedNodes.map((node, idx) => {
                  const firstLine = Math.min(...node.mentionLines);
                  const isGlobal = node.id === "__global__" || node.name.toLowerCase().includes("global");
                  const mentionGroups = groupMentionLines(node.mentionLines);
                  const isExpanded = !!expandedMentionsByNode[node.id];
                  const flatMentionLines = mentionGroups.flatMap((g) => g.lines);
                  const shownLines = isExpanded ? flatMentionLines : flatMentionLines.slice(0, DEFAULT_MENTIONS_TO_SHOW);
                  const callees = model.edges
                    .filter((e) => e.fromId === node.id)
                    .map((e) => nameById.get(e.toId) ?? e.toId);
                  const showArrow = idx < model.orderedNodes.length - 1;

                  // Para (global), o range L1–L... não diz nada. Mostrar um range informativo.
                  const displayStart =
                    isGlobal && node.mentionLines.length
                      ? Math.max(1, Math.min(...node.mentionLines) - MENTION_CONTEXT_LINES)
                      : node.startLine;
                  const displayEnd =
                    isGlobal && node.mentionLines.length
                      ? Math.min(payload.code.split("\n").length, Math.max(...node.mentionLines) + MENTION_CONTEXT_LINES)
                      : node.endLine;

                  return (
                    <div key={node.id}>
                      <div
                        className={`rounded-md border px-2 py-2 font-mono text-[11px] ${
                          node.isOrigin
                            ? "border-primary/60 bg-primary/10"
                            : "border-border/60 bg-muted/20"
                        }`}
                      >
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <span className="font-semibold text-foreground truncate">{node.name}</span>
                          {node.isOrigin && (
                            <span className="shrink-0 text-[9px] uppercase tracking-wide text-primary">Origem</span>
                          )}
                        </div>
                        <div className="text-muted-foreground text-[10px] mb-1.5">
                          L{displayStart}–L{displayEnd} · {formatMentions(node.mentionLines.length)}
                        </div>
                        {callees.length > 0 && (
                          <div className="text-[10px] text-muted-foreground mb-1.5">
                            Chama: <span className="text-foreground">{callees.join(", ")}</span>
                          </div>
                        )}
                        <pre className="mt-1 max-h-28 overflow-auto rounded bg-code-bg/80 p-2 text-[10px] leading-snug text-foreground/90 whitespace-pre border border-border/40">
                          {snippetAroundLine(payload.code, firstLine, 2)}
                        </pre>
                        <div className="mt-1.5 flex flex-wrap gap-1 items-center">
                          {shownLines.map((ln) => (
                            <button
                              key={ln}
                              type="button"
                              onClick={() => {
                                // Mostrar uma janela leve à volta da menção (±N linhas) e ir "carregando"
                                // mais à medida que o utilizador faz scroll.
                                setWindowFocusLine(ln);
                                setScrollToLine(ln);
                                setTimeout(() => setScrollToLine(null), 2200);
                              }}
                              className="rounded px-1.5 py-0.5 text-[10px] bg-secondary/80 text-foreground hover:bg-primary/20 hover:text-primary transition-colors"
                            >
                              L{ln}
                            </button>
                          ))}
                          {flatMentionLines.length > DEFAULT_MENTIONS_TO_SHOW && (
                            <button
                              type="button"
                              onClick={() =>
                                setExpandedMentionsByNode((prev) => ({ ...prev, [node.id]: !isExpanded }))
                              }
                              className="rounded px-1.5 py-0.5 text-[10px] border border-border/60 bg-muted/30 text-muted-foreground hover:bg-muted/50 hover:text-foreground transition-colors"
                              title={isExpanded ? "Mostrar menos menções" : "Mostrar mais menções"}
                            >
                              {isExpanded
                                ? "Mostrar menos"
                                : `+${(flatMentionLines.length - DEFAULT_MENTIONS_TO_SHOW).toLocaleString()}`}
                            </button>
                          )}
                        </div>
                        {mentionGroups.length > 1 && (
                          <div className="mt-1 text-[10px] text-muted-foreground">
                            {mentionGroups.length.toLocaleString()} grupo{mentionGroups.length !== 1 ? "s" : ""} de menções
                          </div>
                        )}
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
                windowFocusLine={windowFocusLine}
                windowContextLines={MENTION_CONTEXT_LINES}
                windowChunkLines={MENTION_CHUNK_LINES}
                windowMaxLines={MENTION_WINDOW_MAX_LINES}
                selectedWord={payload.word}
                onWordSelect={handleWordSelect}
                flaggedIndicators={payload.flaggedIndicators ?? undefined}
                downloadFileName={`${baseName}.c`}
                maxInitialLines={4000}
                hideLimitNotice
              />
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

export default XrefExplorerPage;
