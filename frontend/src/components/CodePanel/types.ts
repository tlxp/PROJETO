import type React from "react";

export type DisplayLineRange = { start: number; end: number };

/** Bloco foldável: linha que abre com "{" até à linha que fecha com "}". */
export type FoldBlock = { startLine: number; endLine: number };

export type FunctionHighlight = {
  id: string;
  name: string;
  startLine: number;
  endLine: number;
  severity?: string;
  score?: number;
  indicators?: string[];
  reasons?: string[];
};

export type Row =
  | { type: "code"; lineNumber: number; line: string }
  | { type: "gap"; start: number; end: number }
  | { type: "foldPlaceholder"; startLine: number; endLine: number };

export interface CodePanelProps {
  title: string;
  language: string;
  code: string;
  icon?: React.ReactNode;
  scrollToLine?: number | null;
  onExpand?: () => void;
  compactHeader?: boolean;
  /** Quando true, remove moldura externa (para embutir num container com border próprio). */
  embedded?: boolean;
  /** Número máximo de linhas a renderizar inicialmente (para ficheiros muito grandes). */
  maxInitialLines?: number;
  /** Mostrar apenas estas faixas de linhas (ex.: funções com flag). Mantém numeração original. */
  displayLineRanges?: DisplayLineRange[] | null;
  /** Nome do ficheiro para o botão "Descarregar" (ex.: "output.c"). Omitir para esconder o botão. */
  downloadFileName?: string | null;
  /**
   * Modo leve: mostra apenas uma janela de linhas à volta desta linha.
   * Útil para clicar num marcador e ver ±N linhas.
   */
  windowFocusLine?: number | null;
  /** Quantas linhas acima/abaixo mostrar no modo janela. Default: 1000. */
  windowContextLines?: number;
  /** Quantas linhas deslocar a janela por vez ao fazer scroll. Default: 400. */
  windowChunkLines?: number;
  /** Limite máximo de linhas a manter em memória/render no modo janela (antes de começar a deslizar). Default: 2500. */
  windowMaxLines?: number;
  /** Intervalo de linhas a destacar temporariamente ao clicar na barra lateral (scroll + destaque que desaparece). */
  highlightedLineRange?: { start: number; end: number } | null;
  /** Intervalos das funções suspeitas: destaque permanente apenas na primeira e última linha de cada. */
  permanentHighlightRanges?: DisplayLineRange[] | null;
  /** Destaques de funções (ex.: suspeitas): aplica highlight ao corpo inteiro e permite tooltips/seleção. */
  functionHighlights?: FunctionHighlight[] | null;
  /** Notifica a linha "atual" no viewport (para sincronizar a barra lateral). */
  onViewportLineChange?: (line: number) => void;
  /** Mostrar a mensagem de aviso quando só estão visíveis funções com flag. */
  showDisplayRangesNotice?: boolean;
  /** Keywords/indicadores que levaram à suspeição (ex.: GetAsyncKeyState) — destacados no texto como maliciosos. */
  flaggedIndicators?: string[] | null;
  /** Palavra selecionada (duplo-clique): mostra referências à direita e highlight no código. */
  selectedWord?: string | null;
  /** Callback quando o utilizador seleciona uma palavra (duplo-clique). */
  onWordSelect?: (word: string) => void;
  /** Esconder aviso de limite de linhas e botão "Mostrar tudo". */
  hideLimitNotice?: boolean;
  /** Esconder aviso de modo janela (±N linhas) no fundo do painel. */
  hideWindowNotice?: boolean;
  /** Notifica o range atual do modo janela (para footers externos). */
  onWindowRangeChange?: (range: { start: number; end: number; totalLines: number }) => void;
  /** Quando true, remove scrolling (painel fica estático). */
  disableScroll?: boolean;
  /** Mostra botão Gemini para explicar o excerto de código C visível. */
  geminiAssist?: boolean;
  /** Permite respostas simuladas (apenas no layout de demonstração mock). */
  geminiAllowMock?: boolean;
}
