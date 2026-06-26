// --- Módulo: geminiApiKey.ts ---
// Armazenamento local da chave API Gemini.

const STORAGE_KEY = "rat-analyzer.gemini-api-key";

// --- Leitura e escrita ---
export function getGeminiApiKey(): string | null {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value?.trim() ? value.trim() : null;
  } catch {
    return null;
  }
}

export function setGeminiApiKey(key: string): void {
  const trimmed = key.trim();
  if (!trimmed) {
    clearGeminiApiKey();
    return;
  }
  localStorage.setItem(STORAGE_KEY, trimmed);
}

export function clearGeminiApiKey(): void {
  localStorage.removeItem(STORAGE_KEY);
}
