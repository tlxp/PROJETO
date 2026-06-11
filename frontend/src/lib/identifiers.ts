/** Validação e escaping de identificadores usados para construir RegExp dinâmicas. */

export const IDENTIFIER_RE = /^[A-Za-z_$][\w$]*$/;

/** True se a palavra for um identificador C/C#-like seguro para usar em RegExp. */
export function isValidIdentifier(word: string): boolean {
  return IDENTIFIER_RE.test(word);
}

export function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
