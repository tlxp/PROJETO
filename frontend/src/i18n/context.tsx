// --- Módulo: context.tsx ---
// Provider React e helpers de tradução (dentro e fora de componentes).

import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  CATALOG,
  STORAGE_KEY,
  formatMessage,
  normalizeLang,
  readInitialLang,
  readLangFromUrl,
} from "./messages";
import type { Lang, Messages } from "./types";

type I18nContextValue = {
  lang: Lang;
  messages: Messages;
  t: (key: keyof Messages, vars?: Record<string, string | number>) => string;
  setLang: (lang: Lang) => void;
};

const I18nContext = createContext<I18nContextValue | null>(null);

function applyDocumentLang(lang: Lang) {
  if (typeof document !== "undefined") {
    document.documentElement.lang = lang === "en" ? "en" : "pt";
  }
}

// --- Provider ---
export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLangState] = useState<Lang>(() => readInitialLang());

  const setLang = useCallback((next: Lang) => {
    setLangState(next);
    if (typeof window !== "undefined") {
      localStorage.setItem(STORAGE_KEY, next);
      const url = new URL(window.location.href);
      url.searchParams.set("lang", next);
      window.history.replaceState(null, "", url.toString());
    }
    applyDocumentLang(next);
  }, []);

  useEffect(() => {
    const fromUrl = readLangFromUrl();
    if (fromUrl && fromUrl !== lang) {
      setLangState(fromUrl);
      localStorage.setItem(STORAGE_KEY, fromUrl);
    }
    applyDocumentLang(fromUrl ?? lang);
  }, [lang]);

  const messages = CATALOG[lang];

  const t = useCallback(
    (key: keyof Messages, vars?: Record<string, string | number>) => {
      const template = messages[key] ?? CATALOG.pt[key] ?? String(key);
      return vars ? formatMessage(template, vars) : template;
    },
    [messages]
  );

  const value = useMemo(() => ({ lang, messages, t, setLang }), [lang, messages, t, setLang]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

// --- Hook React ---
export function useI18n(): I18nContextValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used within I18nProvider");
  return ctx;
}

// --- Helpers fora de React ---
export function getLang(): Lang {
  if (typeof window !== "undefined") {
    const fromUrl = readLangFromUrl();
    if (fromUrl) return fromUrl;
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) return normalizeLang(stored);
  }
  return normalizeLang(import.meta.env.VITE_DEFAULT_LOCALE);
}

export function getT(key: keyof Messages, vars?: Record<string, string | number>): string {
  const lang = getLang();
  const template = CATALOG[lang][key] ?? CATALOG.pt[key] ?? String(key);
  return vars ? formatMessage(template, vars) : template;
}

export function getAcceptLanguage(): string {
  return getLang() === "en" ? "en-US,en;q=0.9" : "pt-PT,pt;q=0.9";
}
