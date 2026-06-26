// --- Módulo: cBlockUtils.ts ---
// Deteção de blocos delimitados por chavetas `{` `}` em código C/pseudo-C.

export type BraceBlock = { start: number; end: number };

// --- Blocos por equilíbrio de chavetas ---
// *Cada bloco vai da linha da `{` de abertura até à `}` de fecho correspondente*
export function getBraceBlocksFromLines(lines: string[]): BraceBlock[] {
  const blocks: BraceBlock[] = [];
  const stack: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;
    for (let o = 0; o < opens; o++) stack.push(i + 1);
    for (let c = 0; c < closes; c++) {
      if (stack.length > 0) {
        const start = stack.pop()!;
        blocks.push({ start, end: i + 1 });
      }
    }
  }
  return blocks;
}

// --- Atalho a partir de texto completo ---
export function getBraceBlocksFromCode(code: string): BraceBlock[] {
  return getBraceBlocksFromLines(code.split("\n"));
}
