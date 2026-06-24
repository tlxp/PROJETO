// --- Módulo: codepanel-utils.test.ts ---
import { describe, it, expect } from "vitest";
import { getFoldBlocks } from "@/components/CodePanel/utils";

// --- Testes: getFoldBlocks ---
describe("getFoldBlocks", () => {
// --- Verifica: encontra blocos simples { } por linha ---
  it("encontra blocos simples { } por linha", () => {
    const lines = ["int f() {", "  return 1;", "}"];
    expect(getFoldBlocks(lines)).toEqual([{ startLine: 1, endLine: 3 }]);
  });

// --- Verifica: suporta blocos aninhados (inner fecha primeiro) ---
  it("suporta blocos aninhados (inner fecha primeiro)", () => {
    const lines = [
      "void f() {",   // 1
      "  if (x) {",   // 2
      "    g();",     // 3
      "  }",          // 4
      "}",            // 5
    ];
    expect(getFoldBlocks(lines)).toEqual([
      { startLine: 2, endLine: 4 },
      { startLine: 1, endLine: 5 },
    ]);
  });

// --- Verifica: ignora chavetas de fecho sem abertura correspondente ---
  it("ignora chavetas de fecho sem abertura correspondente", () => {
    const lines = ["}", "int f() {", "}"];
    expect(getFoldBlocks(lines)).toEqual([{ startLine: 2, endLine: 3 }]);
  });

// --- Verifica: devolve vazio para código sem blocos ---
  it("devolve vazio para código sem blocos", () => {
    expect(getFoldBlocks(["int x = 1;", "x++;"])).toEqual([]);
  });
});
