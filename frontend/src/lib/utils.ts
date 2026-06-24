// --- Módulo: utils.ts ---
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// --- Combina classes Tailwind sem conflitos ---
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
