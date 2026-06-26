// --- Módulo: mockDemoEnabled.test.ts ---
import { afterEach, describe, expect, it, vi } from "vitest";
import { isMockDemoEnabled } from "@/lib/mockDemoEnabled";

describe("isMockDemoEnabled", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("devolve false em produção mesmo com ?demo=1", () => {
    vi.stubEnv("DEV", false);
    vi.stubEnv("VITE_ENABLE_MOCK_DEMO", "true");
    expect(isMockDemoEnabled("?demo=1")).toBe(false);
  });

  it("devolve true em dev com ?demo=1", () => {
    vi.stubEnv("DEV", true);
    expect(isMockDemoEnabled("?demo=1")).toBe(true);
  });

  it("devolve true em dev com VITE_ENABLE_MOCK_DEMO=true", () => {
    vi.stubEnv("DEV", true);
    vi.stubEnv("VITE_ENABLE_MOCK_DEMO", "true");
    expect(isMockDemoEnabled("")).toBe(true);
  });

  it("devolve false em dev sem flag nem query", () => {
    vi.stubEnv("DEV", true);
    vi.stubEnv("VITE_ENABLE_MOCK_DEMO", "");
    expect(isMockDemoEnabled("")).toBe(false);
  });
});
