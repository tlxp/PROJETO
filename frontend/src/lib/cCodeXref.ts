// --- Módulo: cCodeXref.ts ---
// Referências cruzadas no pseudo-C (heurísticas tipo Ghidra/IDA).

import { escapeRegex, isValidIdentifier } from "./identifiers";
import { getCBlocks } from "./analysis";

export type CBlock = { start: number; end: number };

export type XrefFunctionNode = {
  id: string;
  name: string;
  startLine: number;
  endLine: number;
  mentionLines: number[];
  isOrigin: boolean;
  // *Linha exata da definição/assinatura do símbolo*
  originDeclLine?: number;
};

export type XrefEdge = {
  fromId: string;
  toId: string;
};

export type XrefViewModel = {
  symbol: string;
  origin: XrefFunctionNode | null;
  // *Linha exata da definição/assinatura do símbolo*
  originDeclLine: number | null;
  // *Ordem: origem primeiro, depois BFS por chamadas, restantes por linha*
  orderedNodes: XrefFunctionNode[];
  edges: XrefEdge[];
};

function inferFunctionName(lines: string[], block: CBlock): string {
  const s0 = block.start - 1;
  // Heurística:
  // - o bloco pode começar na linha "{" (assinatura na linha anterior)
  // - a assinatura pode estar na mesma linha do "{"
  // - a assinatura pode estar partida por várias linhas acima do "{"
  const parts: string[] = [];
  const startScan = Math.max(0, s0);
  const endScan = Math.max(0, startScan - 6); // procurar até 6 linhas acima
  for (let i = startScan; i >= endScan; i--) {
    const raw = lines[i] ?? "";
    const t = raw.trim();
    if (!t) continue;
    // ignorar só chavetas/labels vazias
    if (t === "{") continue;
    parts.unshift(t);
    // se já temos parênteses, é provável que seja assinatura suficiente
    if (t.includes("(") && (t.includes(")") || parts.join(" ").includes(")"))) break;
  }
  const sig = parts.join(" ");
  // Remover tudo a partir da chaveta para o regex funcionar.
  const cleaned = sig.replace(/\{.*$/, "").trim();
  const m = cleaned.match(/\b([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*;?\s*$/);
  if (m) return m[1];
  const toks = cleaned.split(/\s+/).filter(Boolean);
  for (let i = toks.length - 1; i >= 0; i--) {
    const t = toks[i];
    if (
      /^[A-Za-z_$][\w$]*$/.test(t) &&
      !/^(void|int|char|long|short|double|float|bool|unsigned|static|const|struct|union|enum|inline|undefined\d*|byte|sbyte|ushort|uint|ulong)$/.test(t)
    ) {
      return t;
    }
  }
  return `L${block.start}`;
}

function findMentionLines(code: string, word: string): number[] {
  if (!word || word.length < 2) return [];
  const escaped = escapeRegex(word);
  const re = new RegExp("\\b" + escaped + "\\b");
  const lines = code.split("\n");
  const out: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    re.lastIndex = 0;
    if (re.test(lines[i])) out.push(i + 1);
  }
  return out;
}

function blockContainsLine(block: CBlock | { start: number; end: number }, line: number): boolean {
  return line >= block.start && line <= block.end;
}

// --- Heurísticas de origem e grafo ---
function findOriginLine(code: string, word: string): number | null {
  if (!word || word.length < 2) return null;
  const escaped = escapeRegex(word);
  const lines = code.split("\n");
  const cTypeRe = new RegExp(
    "\\b(int|void|char|long|short|float|double|bool|unsigned|size_t|uint\\w*|struct\\s+\\w+|undefined\\w*|byte|sbyte|ushort|uint|ulong)\\s+" + escaped + "\\b"
  );
  const csTypeRe = new RegExp(
    "\\b(string|var|bool|int|long|float|double|object|decimal)\\s+" + escaped + "\\b"
  );
  const paramRe = new RegExp(
    "[,(]\\s*(?:const\\s+)?(?:int|void|char|long|short|float|double|bool|unsigned|string|var)\\s+" + escaped + "\\s*[),]",
    "i"
  );
  // Definição de função: pode ter "{" na mesma linha OU na linha seguinte.
  const funcSigRe = new RegExp("\\b" + escaped + "\\s*\\([^)]*\\)\\s*$");
  const funcDefSameLineRe = new RegExp("\\b" + escaped + "\\s*\\([^)]*\\)\\s*\\{");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // 1) Se for uma definição de função, priorizar como origem.
    if (funcDefSameLineRe.test(line)) return i + 1;
    if (funcSigRe.test(line)) {
      // procurar próxima linha "{" (ignorando vazios)
      for (let j = i + 1; j < Math.min(lines.length, i + 6); j++) {
        const t = lines[j]?.trim() ?? "";
        if (!t) continue;
        if (t === "{") return i + 1;
        break;
      }
    }

    // 2) Caso geral: declaração/uso "tipo símbolo", parâmetro, etc.
    if (cTypeRe.test(line) || csTypeRe.test(line) || paramRe.test(line)) {
      return i + 1;
    }
  }
  return null;
}

function buildCallEdges(
  code: string,
  blocks: CBlock[],
  names: Map<string, string>
): XrefEdge[] {
  const lines = code.split("\n");
  const edges: XrefEdge[] = [];
  const seen = new Set<string>();

  for (const b of blocks) {
    const fromId = names.get(`${b.start}:${b.end}`);
    if (!fromId) continue;
    const fromName = inferFunctionName(lines, b);
    const body = lines.slice(b.start - 1, b.end).join("\n");
    for (const [coordKey, toId] of names) {
      if (toId === fromId) continue;
      const [ts, te] = coordKey.split(":").map((x) => parseInt(x, 10));
      const toBlock = { start: ts, end: te } as CBlock;
      const toName = inferFunctionName(lines, toBlock);
      if (toName === fromName) continue;
      const callRe = new RegExp("\\b" + escapeRegex(toName) + "\\s*\\(");
      if (callRe.test(body)) {
        const ek = `${fromId}->${toId}`;
        if (!seen.has(ek)) {
          seen.add(ek);
          edges.push({ fromId, toId });
        }
      }
    }
  }
  return edges;
}

export function buildXrefViewModel(code: string, word: string): XrefViewModel {
  const symbol = word.trim();
  // Validação do identificador (a palavra pode vir de um URL) antes de construir RegExp.
  if (!symbol || symbol.length < 2 || !code || !isValidIdentifier(symbol)) {
    return { symbol, origin: null, originDeclLine: null, orderedNodes: [], edges: [] };
  }

  const lines = code.split("\n");
  const mentionLines = findMentionLines(code, symbol);
  const allBlocks = getCBlocks(code);
  const originLine = findOriginLine(code, symbol);

  // Em pseudo-C (Ghidra/IDA), a definição da função (assinatura) costuma estar ANTES do "{",
  // e o nosso `getCBlocks` define `start` como a linha DEPOIS do "{". Isso fazia com que:
  // - a linha de definição não pertencesse a nenhum bloco
  // - o bloco da função de origem não fosse criado (se não tivesse menções no corpo)
  // - a "Origem" caísse para a primeira menção noutra função
  //
  // Para resolver, mapeamos a `originLine` para o bloco top-level que começa logo a seguir.
  const originBlockKey = (() => {
    if (originLine == null) return null;
    const maxLookahead = 12; // assinatura + linhas vazias + "{"
    const b = allBlocks.find((blk) => blk.start > originLine && blk.start - originLine <= maxLookahead) ?? null;
    return b ? `${b.start}:${b.end}` : null;
  })();

  const rawNodes: XrefFunctionNode[] = [];
  const names = new Map<string, string>();

  for (const b of allBlocks) {
    let hits = mentionLines.filter((ln) => blockContainsLine(b, ln));
    const isOriginBlock = originBlockKey != null && originBlockKey === `${b.start}:${b.end}`;
    const touchesOriginDecl = isOriginBlock;
    // Se não há menções no corpo, só criamos o nó se for o bloco de origem.
    if (hits.length === 0 && !isOriginBlock) continue;

    const id = `f-${b.start}-${b.end}`;
    // `names` deve conter apenas nós que realmente existem no grafo,
    // caso contrário as arestas apontam para IDs sem nome (aparecem como "f-123-456" na UI).
    names.set(`${b.start}:${b.end}`, id);

    // Se a origem é a definição do próprio símbolo (ex.: "fortnite(...) {"),
    // não queremos contar essa linha como "menção" (menções = referências/uses).
    if (touchesOriginDecl && originLine != null) {
      hits = hits.filter((ln) => ln !== originLine);
    }
    rawNodes.push({
      id,
      name: inferFunctionName(lines, b),
      startLine: b.start,
      endLine: b.end,
      mentionLines: hits,
      isOrigin: touchesOriginDecl,
      originDeclLine: touchesOriginDecl ? (originLine ?? undefined) : undefined,
    });
  }

  let originId: string | null = null;
  if (originBlockKey != null) {
    const declBlock = rawNodes.find((n) => `${n.startLine}:${n.endLine}` === originBlockKey);
    if (declBlock) originId = declBlock.id;
  }
  if (!originId && rawNodes.length > 0) {
    const sorted = [...rawNodes].sort((a, b) => Math.min(...a.mentionLines) - Math.min(...b.mentionLines));
    originId = sorted[0].id;
  }

  const normalized = rawNodes.map((n) => ({
    ...n,
    isOrigin: originId != null && n.id === originId,
    originDeclLine: originId != null && n.id === originId ? (originLine ?? n.originDeclLine) : undefined,
  }));
  const origin = originId ? normalized.find((n) => n.id === originId) ?? null : null;

  const blockList = normalized.map((n) => ({ start: n.startLine, end: n.endLine }));
  const edges = buildCallEdges(code, blockList, names);

  const idSet = new Set(normalized.map((n) => n.id));
  const adj = new Map<string, string[]>();
  for (const n of normalized) {
    adj.set(n.id, []);
  }
  for (const e of edges) {
    if (!idSet.has(e.fromId) || !idSet.has(e.toId)) continue;
    adj.get(e.fromId)!.push(e.toId);
  }

  const ordered: XrefFunctionNode[] = [];
  const visited = new Set<string>();

  const pushNode = (id: string) => {
    if (visited.has(id)) return;
    const n = normalized.find((x) => x.id === id);
    if (!n) return;
    visited.add(id);
    ordered.push(n);
  };

  if (originId) {
    pushNode(originId);
    const queue = [originId];
    while (queue.length) {
      const u = queue.shift()!;
      for (const v of adj.get(u) ?? []) {
        if (!visited.has(v)) {
          pushNode(v);
          queue.push(v);
        }
      }
    }
  }

  const rest = [...normalized]
    .filter((n) => !visited.has(n.id))
    .sort((a, b) => Math.min(...a.mentionLines) - Math.min(...b.mentionLines));
  for (const n of rest) pushNode(n.id);

  return {
    symbol,
    origin,
    originDeclLine: originLine,
    orderedNodes: ordered,
    edges,
  };
}

export const XREF_SESSION_KEY = "rat-xref-session-v1";

export type XrefSessionPayload = {
  v: 1;
  code: string;
  word: string;
  fileName: string;
  flaggedIndicators?: string[];
};

// --- Sessão e navegação ---
export function writeXrefSession(payload: XrefSessionPayload): void {
  const raw = JSON.stringify(payload);
  // `sessionStorage` não é partilhado entre separadores; o explorador abre em novo tab.
  // Preferimos `localStorage` para garantir que o `/xref` consegue ler o payload.
  try {
    localStorage.setItem(XREF_SESSION_KEY, raw);
    return;
  } catch {
    // ignore (quota, modo privado, bloqueios)
  }
  try {
    sessionStorage.setItem(XREF_SESSION_KEY, raw);
  } catch {
    // ignore
  }
}

export function readXrefSession(): XrefSessionPayload | null {
  try {
    const raw =
      localStorage.getItem(XREF_SESSION_KEY) ??
      sessionStorage.getItem(XREF_SESSION_KEY);
    if (!raw) return null;
    const p = JSON.parse(raw) as XrefSessionPayload;
    if (p?.v !== 1 || typeof p.code !== "string" || typeof p.word !== "string") return null;
    return p;
  } catch {
    return null;
  }
}

export function openXrefExplorerTab(
  href = "/xref",
  _options?: { forceNewTab?: boolean }
): void {
  const path = href.startsWith("/") ? href : `/${href}`;
  const base = (import.meta.env.BASE_URL || "/").replace(/\/?$/, "/");
  const url = base === "/" ? path : `${base}${path.replace(/^\//, "")}`;
  window.open(url, "_blank", "noopener,noreferrer");
}
