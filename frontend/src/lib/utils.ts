// --- Módulo: utils.ts ---
// Combina classes Tailwind sem conflitos (clsx + tailwind-merge).

import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
