/**
 * Rotas canónicas da SPA — única fonte para paths de navegação (não confundir com /api/*).
 */
export const ROUTES = {
  home: "/",
  analysis: (jobId: string) => `/analysis/${encodeURIComponent(jobId)}`,
  analysisXref: (jobId: string, word?: string) => {
    const base = `/analysis/${encodeURIComponent(jobId)}/xref`;
    return word ? `${base}?word=${encodeURIComponent(word)}` : base;
  },
  resultadosLegacy: "/resultados",
  xrefLegacy: (word?: string) =>
    word ? `/xref?word=${encodeURIComponent(word)}` : "/xref",
} as const;

/** Paths usados em `<Route path="…">` (React Router). */
export const ROUTE_PATTERNS = {
  home: "/",
  analysis: "/analysis/:jobId",
  analysisXref: "/analysis/:jobId/xref",
  resultadosLegacy: "/resultados",
  xrefLegacy: "/xref",
  notFound: "*",
} as const;
