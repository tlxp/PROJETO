// --- Módulo: gemini.test.ts ---
// Testes do excerto de código e respostas mock do assistente Gemini.

import { describe, it, expect } from "vitest";
import { buildCodeExcerpt, GEMINI_CODE_CHAR_LIMIT, getGeminiMockReply } from "@/lib/gemini";

describe("buildCodeExcerpt", () => {
  const lines = ["line1", "line2", "line3", "line4", "line5"];

  it("usa displayLineRanges quando definido", () => {
    const result = buildCodeExcerpt(lines, {
      displayLineRanges: [{ start: 2, end: 3 }],
    });
    expect(result.text).toBe("line2\nline3");
    expect(result.lineInfo).toBe("linhas 2–3");
    expect(result.truncated).toBe(false);
  });

  it("usa janela visível no modo window", () => {
    const result = buildCodeExcerpt(lines, {
      windowStart: 2,
      windowEnd: 4,
    });
    expect(result.text).toBe("line2\nline3\nline4");
    expect(result.lineInfo).toBe("linhas 2–4");
  });

  it("trunca quando excede o limite de caracteres", () => {
    const longLines = Array.from({ length: 5 }, () => "x".repeat(5000));
    const result = buildCodeExcerpt(longLines, { showAll: true, charLimit: 100 });
    expect(result.truncated).toBe(true);
    expect(result.text.length).toBeGreaterThan(100);
    expect(result.text).toContain("truncado");
    expect(GEMINI_CODE_CHAR_LIMIT).toBeGreaterThan(100);
  });

  it("devolve resposta mock em português", () => {
    const reply = getGeminiMockReply("O que faz?", "linhas 1–50");
    expect(reply).toContain("demonstração");
    expect(reply).toContain("linhas 1–50");
  });
});
