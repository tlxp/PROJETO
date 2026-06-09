import type { FoldBlock } from "./types";

/** Encontra todos os blocos { } no código (por linha). */
export function getFoldBlocks(lines: string[]): FoldBlock[] {
  const blocks: FoldBlock[] = [];
  const stack: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;
    for (let o = 0; o < opens; o++) stack.push(i + 1);
    for (let c = 0; c < closes; c++) {
      if (stack.length > 0) {
        const start = stack.pop()!;
        blocks.push({ startLine: start, endLine: i + 1 });
      }
    }
  }
  return blocks;
}
