// --- Módulo: utils.ts ---
// Utilitários do CodePanel (blocos foldáveis).

import { getBraceBlocksFromLines } from "@/lib/cBlockUtils";
import type { FoldBlock } from "./types";

// --- Blocos foldáveis ---
// *Delega a deteção de chavetas ao util partilhado cBlockUtils*
export function getFoldBlocks(lines: string[]): FoldBlock[] {
  return getBraceBlocksFromLines(lines).map((b) => ({
    startLine: b.start,
    endLine: b.end,
  }));
}
