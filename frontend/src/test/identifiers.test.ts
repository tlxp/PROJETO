// --- Módulo: identifiers.test.ts ---
import { describe, it, expect } from "vitest";
import { escapeRegex, isValidIdentifier } from "@/lib/identifiers";

// --- Testes: isValidIdentifier ---
describe("isValidIdentifier", () => {
// --- Verifica: aceita identificadores C/C#-like ---
  it("aceita identificadores C/C#-like", () => {
    expect(isValidIdentifier("foo")).toBe(true);
    expect(isValidIdentifier("_bar42")).toBe(true);
    expect(isValidIdentifier("$jquery")).toBe(true);
    expect(isValidIdentifier("FUN_10001020")).toBe(true);
  });

// --- Verifica: rejeita texto arbitrário selecionado ---
  it("rejeita texto arbitrário selecionado", () => {
    expect(isValidIdentifier("")).toBe(false);
    expect(isValidIdentifier("42abc")).toBe(false);
    expect(isValidIdentifier("a b")).toBe(false);
    expect(isValidIdentifier("a+b")).toBe(false);
    expect(isValidIdentifier("foo()")).toBe(false);
    expect(isValidIdentifier(".*")).toBe(false);
  });
});

// --- Testes: escapeRegex ---
describe("escapeRegex", () => {
// --- Verifica: escapa todos os metacaracteres de RegExp ---
  it("escapa todos os metacaracteres de RegExp", () => {
    const raw = ".*+?^${}()|[]\\";
    const escaped = escapeRegex(raw);
    // O resultado deve poder ser compilado e dar match literal.
    const re = new RegExp(escaped);
    expect(re.test(raw)).toBe(true);
  });

// --- Verifica: não altera identificadores normais ---
  it("não altera identificadores normais", () => {
    expect(escapeRegex("GetAsyncKeyState")).toBe("GetAsyncKeyState");
  });
});
