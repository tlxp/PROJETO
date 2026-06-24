// --- Módulo: identifiers.ts ---
// *Validação e escaping de identificadores usados para construir RegExp dinâmicas*

export const IDENTIFIER_RE = /^[A-Za-z_$][\w$]*$/;

// --- Valida identificador C/C#-like seguro para RegExp ---
export function isValidIdentifier(word: string): boolean {
  return IDENTIFIER_RE.test(word);
}

// --- Escapa caracteres especiais para uso em RegExp ---
export function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
