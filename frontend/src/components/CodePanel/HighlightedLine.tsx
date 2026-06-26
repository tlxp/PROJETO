// --- Módulo: HighlightedLine.tsx ---
// Renderização de linha com syntax highlight e destaques.

import React from "react";

const MALICIOUS_CLASS = "bg-destructive/25 text-destructive font-medium";
const SELECTED_WORD_CLASS = "bg-primary/25 text-primary font-medium rounded-sm";
const SELECTED_WORD_PRIORITY = -1;
const MALICIOUS_PRIORITY = 0;
const SYNTAX_PRIORITY = 1;

type StyledSpan = { start: number; end: number; className: string; priority: number };

function renderStyledLine(line: string, spans: StyledSpan[]): React.ReactNode {
  if (spans.length === 0) {
    return <span className="text-foreground">{line}</span>;
  }

  const classes = new Array<string | null>(line.length).fill(null);
  const priorities = new Array<number>(line.length).fill(Number.POSITIVE_INFINITY);

  for (const span of spans) {
    const start = Math.max(0, span.start);
    const end = Math.min(line.length, span.end);
    for (let i = start; i < end; i++) {
      if (span.priority < priorities[i]) {
        priorities[i] = span.priority;
        classes[i] = span.className;
      }
    }
  }

  const elements: React.ReactNode[] = [];
  let i = 0;
  while (i < line.length) {
    const cls = classes[i];
    let j = i + 1;
    while (j < line.length && classes[j] === cls) j++;
    const text = line.slice(i, j);
    if (cls) {
      elements.push(
        <span key={i} className={cls}>
          {text}
        </span>
      );
    } else {
      elements.push(
        <span key={`t${i}`} className="text-foreground">
          {text}
        </span>
      );
    }
    i = j;
  }

  return <>{elements}</>;
}

// --- Componente ---
export const HighlightedLine: React.FC<{
  line: string;
  language: string;
  highlightTokens?: string[] | null;
  highlightWord?: string | null;
}> = ({ line, language, highlightTokens, highlightWord }) => {
  if (language === "report") {
    const trimmed = line.trim();
    if (!trimmed) {
      return <span className="block h-2" />;
    }

    // Linhas de separador (==== / ----) -> linha horizontal suave
    if (/^[=-]{5,}$/.test(trimmed)) {
      return <span className="block border-b border-border/40 my-1" />;
    }

    // Título principal (estático ou VM)
    if (/^RELATÓRIO DE ANÁLISE/i.test(trimmed)) {
      return (
        <span className="block text-sm font-semibold text-code-function mb-1">
          {trimmed}
        </span>
      );
    }

    // Alertas do relatório VM
    if (trimmed.startsWith("[ERRO]")) {
      return (
        <span className="block pl-3 text-[11px] text-destructive font-medium mb-[2px]">
          {trimmed}
        </span>
      );
    }
    if (trimmed.startsWith("[AVISO]")) {
      return (
        <span className="block pl-3 text-[11px] text-code-string mb-[2px]">
          {trimmed}
        </span>
      );
    }

    // Notas explicativas (execução inconclusiva, benign validation, etc.)
    if (trimmed.startsWith("Nota:")) {
      return (
        <span className="block pl-3 text-[11px] italic text-muted-foreground mb-[2px]">
          {trimmed}
        </span>
      );
    }

    // Cabeçalhos de secção (RESUMO, INFORMAÇÕES DO FICHEIRO, SCORE DE RISCO, etc.)
    const isAllCaps =
      /^[A-Z0-9ÁÀÂÃÉÈÊÍÓÔÕÚÇ ,./()-]+$/.test(trimmed) && trimmed.length <= 80;
    if (isAllCaps) {
      return (
        <span className="block border-l-2 border-code-function/60 pl-3 text-xs font-semibold text-code-function mt-2 mb-1 tracking-wide">
          {trimmed}
        </span>
      );
    }

    // Bullets / listas
    if (trimmed.startsWith("- ") || trimmed.startsWith("• ") || /^\s*-\s+/.test(line)) {
      return (
        <span className="block pl-4 text-[11px] text-foreground mb-[2px]">
          {trimmed.replace(/^[-•]\s*/, "• ")}
        </span>
      );
    }

    // Linhas de aviso / warning
    if (trimmed.startsWith("⚠") || trimmed.toUpperCase().includes("WARNING") || trimmed.toUpperCase().includes("AVISO")) {
      return (
        <span className="block pl-3 text-[11px] text-code-string mb-[2px]">
          {trimmed}
        </span>
      );
    }
    // Linhas OK / sucesso
    if (trimmed.startsWith("✓") || trimmed.toUpperCase().includes("OK")) {
      return (
        <span className="block pl-3 text-[11px] text-primary mb-[2px]">
          {trimmed}
        </span>
      );
    }
    // Erros / críticas
    if (trimmed.startsWith("✗") || trimmed.toUpperCase().includes("ERROR") || trimmed.toUpperCase().includes("FALHOU")) {
      return (
        <span className="block pl-3 text-[11px] text-destructive mb-[2px]">
          {trimmed}
        </span>
      );
    }

    // Linhas "label: valor" (Score, Nível, Status, Ficheiro, etc.)
    const colonIdx = trimmed.indexOf(":");
    if (colonIdx > 0 && colonIdx < trimmed.length - 1) {
      const label = trimmed.slice(0, colonIdx).trim();
      const value = trimmed.slice(colonIdx + 1).trim();
      const valueLower = value.toLowerCase();
      let valueClass = "text-muted-foreground";
      if (/^classifica/i.test(label) || /^n[ií]vel/i.test(label)) {
        if (
          valueLower.includes("malicious") ||
          valueLower.includes("malicioso") ||
          valueLower.includes("malici")
        ) {
          valueClass = "text-destructive font-semibold";
        } else if (
          valueLower.includes("suspicious") ||
          valueLower.includes("suspeito") ||
          valueLower.includes("suspeit")
        ) {
          valueClass = "text-code-string font-semibold";
        } else if (
          valueLower.includes("benign") ||
          valueLower.includes("benigno") ||
          valueLower.includes("inofensivo")
        ) {
          valueClass = "text-primary font-semibold";
        }
      } else if (/^score/i.test(label) && /\d+\/100/.test(value)) {
        const scoreNum = parseInt(value, 10);
        if (scoreNum >= 70) valueClass = "text-destructive font-semibold";
        else if (scoreNum >= 35) valueClass = "text-code-string font-semibold";
        else valueClass = "text-primary font-semibold";
      }
      return (
        <span className="block pl-2 text-[11px] leading-relaxed">
          <span className="font-semibold text-foreground">{label}:</span>{" "}
          <span className={valueClass}>{value}</span>
        </span>
      );
    }

    // Linhas informativas negativas (sem deteções)
    if (
      /^Não foram detetad/i.test(trimmed) ||
      /^Sem (alterações|eventos|diferenças)/i.test(trimmed)
    ) {
      return (
        <span className="block pl-3 text-[11px] text-muted-foreground/80 mb-[2px]">
          {trimmed}
        </span>
      );
    }

    // Texto normal do relatório
    return (
      <span className="block pl-1 text-[11px] leading-relaxed text-muted-foreground">
        {trimmed}
      </span>
    );
  }

  // Selected word (duplo-clique) — highlight todas as ocorrências na linha
  const spansWithPriority: StyledSpan[] = [];
  if (highlightWord && highlightWord.length >= 2) {
    const escaped = highlightWord.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp("\\b" + escaped + "\\b", "g");
    let match;
    while ((match = re.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: SELECTED_WORD_CLASS,
        priority: SELECTED_WORD_PRIORITY,
      });
    }
  }

  // Malicious indicators (GetAsyncKeyState, etc.)
  if (highlightTokens && highlightTokens.length > 0 && (language === "C" || language === "c")) {
    const tokens = [...highlightTokens].filter((t) => t && t.length >= 2).sort((a, b) => b.length - a.length);
    for (const token of tokens) {
      let pos = 0;
      while (true) {
        const idx = line.indexOf(token, pos);
        if (idx === -1) break;
        spansWithPriority.push({
          start: idx,
          end: idx + token.length,
          className: MALICIOUS_CLASS,
          priority: MALICIOUS_PRIORITY,
        });
        pos = idx + token.length;
      }
    }
  }

  // Basic keyword highlighting for C/C#
  const keywords = /\b(using|namespace|class|public|private|static|void|int|string|return|if|else|for|while|new|var|const|bool|true|false|null|async|await|override|virtual|abstract|interface|enum|struct|readonly|sealed|partial|get|set|this|base|try|catch|throw|finally)\b/g;
  const strings = /(".*?"|'.*?')/g;
  const comments = /(\/\/.*$|\/\*.*?\*\/)/g;
  const numbers = /\b(\d+\.?\d*)\b/g;
  const types = /\b([A-Z][a-zA-Z0-9]*)\b/g;

  let match;
  comments.lastIndex = 0;
  while ((match = comments.exec(line)) !== null) {
    spansWithPriority.push({
      start: match.index,
      end: match.index + match[0].length,
      className: "text-code-comment",
      priority: SYNTAX_PRIORITY,
    });
  }

  const hasComments = spansWithPriority.some((s) => s.className === "text-code-comment");
  if (!hasComments) {
    strings.lastIndex = 0;
    while ((match = strings.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: "text-code-string",
        priority: SYNTAX_PRIORITY,
      });
    }

    keywords.lastIndex = 0;
    while ((match = keywords.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: "text-code-keyword",
        priority: SYNTAX_PRIORITY,
      });
    }

    types.lastIndex = 0;
    while ((match = types.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: "text-code-type",
        priority: SYNTAX_PRIORITY,
      });
    }

    numbers.lastIndex = 0;
    while ((match = numbers.exec(line)) !== null) {
      spansWithPriority.push({
        start: match.index,
        end: match.index + match[0].length,
        className: "text-code-number",
        priority: SYNTAX_PRIORITY,
      });
    }
  }

  return renderStyledLine(line, spansWithPriority);
};

