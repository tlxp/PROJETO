import { describe, expect, it } from "vitest";
import { ROUTES, ROUTE_PATTERNS } from "@/routes";

describe("routes", () => {
  it("builds encoded analysis permalink", () => {
    expect(ROUTES.analysis("job/with space")).toBe("/analysis/job%2Fwith%20space");
  });

  it("builds xref URL with optional word query", () => {
    expect(ROUTES.analysisXref("abc")).toBe("/analysis/abc/xref");
    expect(ROUTES.analysisXref("abc", "malloc")).toBe("/analysis/abc/xref?word=malloc");
  });

  it("exposes stable React Router patterns", () => {
    expect(ROUTE_PATTERNS.analysis).toBe("/analysis/:jobId");
    expect(ROUTE_PATTERNS.resultadosLegacy).toBe("/resultados");
  });
});
