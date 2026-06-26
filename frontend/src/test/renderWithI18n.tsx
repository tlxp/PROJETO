// --- Módulo: renderWithI18n.tsx ---
// Helper de testes que envolve componentes com I18nProvider em PT.

import React from "react";
import { render, type RenderOptions } from "@testing-library/react";
import { I18nProvider } from "@/i18n";
import { STORAGE_KEY } from "@/i18n/messages";

// --- Render com provider ---
export function renderWithI18n(ui: React.ReactElement, options?: RenderOptions) {
  localStorage.setItem(STORAGE_KEY, "pt");
  return render(<I18nProvider>{ui}</I18nProvider>, options);
}
