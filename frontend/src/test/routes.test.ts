// --- Módulo: routes.test.ts ---
import { describe, expect, it } from "vitest";
import { ROUTES, ROUTE_PATTERNS } from "@/routes";

// --- Testes: routes ---
describe("routes", () => {
// --- Verifica: builds encoded analysis permalink ---
  it("builds encoded analysis permalink", () => {
    expect(ROUTES.analysis("job/with space")).toBe("/analysis/job%2Fwith%20space");
  });

// --- Verifica: builds xref URL with optional word query ---
  it("builds xref URL with optional word query", () => {
    expect(ROUTES.analysisXref("abc")).toBe("/analysis/abc/xref");
    expect(ROUTES.analysisXref("abc", "malloc")).toBe("/analysis/abc/xref?word=malloc");
  });

// --- Verifica: exposes stable React Router patterns ---
  it("exposes stable React Router patterns", () => {
    expect(ROUTE_PATTERNS.analysis).toBe("/analysis/:jobId");
    expect(ROUTE_PATTERNS.resultadosLegacy).toBe("/resultados");
  });
});
