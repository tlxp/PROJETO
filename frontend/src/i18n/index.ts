// --- Módulo: index.ts ---
// Reexportações públicas do pacote i18n.

export type { Lang, Messages } from "./types";
export { I18nProvider, useI18n, getLang, getT, getAcceptLanguage } from "./context";
