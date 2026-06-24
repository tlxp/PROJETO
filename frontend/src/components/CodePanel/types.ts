// --- Módulo: types.ts ---
import type React from "react";

export type DisplayLineRange = { start: number; end: number };

// *Bloco foldável: linha com "{" até linha com "}"*
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
  // *Remove moldura externa (embutir em container com border próprio)*
  embedded?: boolean;
  // *Máximo de linhas renderizadas inicialmente*
  maxInitialLines?: number;
  // *Mostrar apenas faixas de linhas (ex.: funções com flag)*
  displayLineRanges?: DisplayLineRange[] | null;
  // *Nome do ficheiro para botão Descarregar*
  downloadFileName?: string | null;
  // *Modo janela: mostra ±N linhas à volta de windowFocusLine*
  windowFocusLine?: number | null;
  // *Linhas acima/abaixo no modo janela*
  windowContextLines?: number;
  // *Deslocamento da janela por scroll*
  windowChunkLines?: number;
  // *Limite máximo de linhas no modo janela*
  windowMaxLines?: number;
  // *Destaque temporário ao clicar na barra lateral*
  highlightedLineRange?: { start: number; end: number } | null;
  // *Destaque permanente na primeira/última linha de cada função*
  permanentHighlightRanges?: DisplayLineRange[] | null;
  // *Destaques de funções suspeitas (corpo inteiro + tooltips)*
  functionHighlights?: FunctionHighlight[] | null;
  // *Notifica linha atual no viewport (sincronizar barra lateral)*
  onViewportLineChange?: (line: number) => void;
  // *Mostrar aviso quando só funções com flag estão visíveis*
  showDisplayRangesNotice?: boolean;
  // *Keywords/indicadores maliciosos destacados no texto*
  flaggedIndicators?: string[] | null;
  // *Palavra selecionada (duplo-clique) para referências*
  selectedWord?: string | null;
  // *Callback ao selecionar palavra*
  onWordSelect?: (word: string) => void;
  // *Esconder aviso de limite de linhas*
  hideLimitNotice?: boolean;
  // *Esconder aviso de modo janela*
  hideWindowNotice?: boolean;
  // *Notifica range atual do modo janela*
  onWindowRangeChange?: (range: { start: number; end: number; totalLines: number }) => void;
  // *Desativa scrolling*
  disableScroll?: boolean;
  // *Botão Gemini para explicar excerto C*
  geminiAssist?: boolean;
  // *Permite respostas simuladas (layout mock)*
  geminiAllowMock?: boolean;
}
