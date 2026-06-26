// --- Módulo: identifiers.ts ---
// Validação e escaping de identificadores para RegExp dinâmicas.

export const IDENTIFIER_RE = /^[A-Za-z_$][\w$]*$/;

// --- API pública ---
export function isValidIdentifier(word: string): boolean {
  return IDENTIFIER_RE.test(word);
}

export function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
