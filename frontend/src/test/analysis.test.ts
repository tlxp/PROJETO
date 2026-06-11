import { describe, it, expect } from "vitest";
import {
  buildAnalysisResultFromJob,
  normalizeAnalysisResult,
  parseReportCategories,
  parseReportChapters,
  parseReportResumoLines,
  getCBlocks,
  mergeRanges,
  getBlockContainingLine,
  getCDisplayRanges,
  getWordStats,
  clampFlaggedFunctionsToCode,
  isFlaggedRangeInCode,
} from "@/lib/analysis";

const SAMPLE_REPORT = [
  "RELATÓRIO DE ANÁLISE ESTÁTICA",
  "=============================",
  "",
  "SCORE DE RISCO GLOBAL",
  "Score: 92/100",
  "",
  "DETALHE DAS CATEGORIAS",
  "## Suspicious Imports: 4 ocorrências = 15/15 pontos",
  "- Uso de GetAsyncKeyState na linha 42",
  "- Uso de CreateFileA na linha 58",
  "",
  "## Obfuscation: 2 ocorrências = 4/10 pontos",
  "- String concatenation na linha 27",
].join("\n");

const SAMPLE_C_CODE = [
  "// comentário",            // 1
  "int read_config() {",      // 2
  "    int valor = 1;",       // 3
  "    return valor;",        // 4
  "}",                        // 5
  "",                         // 6
  "void exfil_data() {",      // 7
  "    read_config();",       // 8
  "}",                        // 9
].join("\n");

describe("parseReportCategories", () => {
  it("extrai categorias com resumo e linhas de ocorrências", () => {
    const cats = parseReportCategories(SAMPLE_REPORT);
    expect(cats).toHaveLength(2);
    expect(cats[0].label).toContain("Suspicious Imports");
    expect(cats[0].lineNumbers).toEqual([42, 58]);
    expect(cats[1].label).toContain("Obfuscation");
    expect(cats[1].lineNumbers).toEqual([27]);
  });

  it("devolve lista vazia para relatório sem categorias", () => {
    expect(parseReportCategories("sem nada relevante")).toEqual([]);
  });
});

describe("parseReportChapters", () => {
  it("extrai cabeçalhos ALL-CAPS ignorando separadores", () => {
    const chapters = parseReportChapters(SAMPLE_REPORT);
    const labels = chapters.map((c) => c.label);
    expect(labels).toContain("SCORE DE RISCO GLOBAL");
    expect(labels).toContain("DETALHE DAS CATEGORIAS");
    expect(labels).not.toContain("=============================");
  });
});

describe("parseReportResumoLines", () => {
  it("extrai linhas da secção RESUMO até ao próximo cabeçalho", () => {
    const report = ["INTRO", "RESUMO", "Linha A", "Linha B", "SCORE DE RISCO:", "x"].join("\n");
    expect(parseReportResumoLines(report)).toEqual(["Linha A", "Linha B"]);
  });

  it("devolve null se não houver RESUMO", () => {
    expect(parseReportResumoLines(SAMPLE_REPORT)).toBeNull();
  });
});

describe("buildAnalysisResultFromJob", () => {
  it("usa staticResult quando presente (incluindo flaggedFunctions)", () => {
    const job = {
      status: "completed",
      staticResult: {
        report: "R",
        cCode: "C",
        ilCode: "IL",
        fileName: "evil.exe",
        riskScore: 80,
        riskLevel: "ALTO",
        flaggedIndicators: ["GetAsyncKeyState", 42],
        flaggedFunctions: [
          { name: "f", startLine: 1, endLine: 3, indicators: ["x"], score: 50 },
          "inválido",
        ],
      },
    };
    const res = buildAnalysisResultFromJob(job);
    expect(res).not.toBeNull();
    expect(res?.fileName).toBe("evil.exe");
    expect(res?.riskScore).toBe(80);
    expect(res?.flaggedIndicators).toEqual(["GetAsyncKeyState"]);
    expect(res?.flaggedFunctions).toHaveLength(1);
    expect(res?.flaggedFunctions?.[0]).toMatchObject({ name: "f", startLine: 1, endLine: 3, score: 50 });
  });

  it("aceita staticResult serializado como string JSON", () => {
    const job = { staticResult: JSON.stringify({ report: "R", riskScore: 10 }) };
    const res = buildAnalysisResultFromJob(job, "fallback.bin");
    expect(res?.report).toBe("R");
    expect(res?.riskScore).toBe(10);
    expect(res?.fileName).toBe("fallback.bin");
  });

  it("constrói resultado a partir de dynamicResult quando não há staticResult", () => {
    const job = { dynamicResult: { dynamicSummary: "ok", dynamicReport: { a: 1 } } };
    const res = buildAnalysisResultFromJob(job, "x.exe");
    expect(res?.dynamicSummary).toBe("ok");
    expect(res?.report).toContain("Análise dinâmica");
    expect(res?.cCode).toBe("");
  });

  it("usa campos no root como fallback (payloads antigos)", () => {
    const res = buildAnalysisResultFromJob({ report: "root", cCode: "c" });
    expect(res?.report).toBe("root");
    expect(res?.cCode).toBe("c");
  });

  it("devolve null para payloads sem resultado", () => {
    expect(buildAnalysisResultFromJob(null)).toBeNull();
    expect(buildAnalysisResultFromJob({ status: "running" })).toBeNull();
  });
});

describe("normalizeAnalysisResult", () => {
  it("aplica defaults seguros a campos em falta ou de tipo errado", () => {
    const res = normalizeAnalysisResult({ riskScore: "92", report: 5 }, "file.exe");
    expect(res.report).toBe("");
    expect(res.riskScore).toBe(0);
    expect(res.fileName).toBe("file.exe");
    expect(res.flaggedIndicators).toEqual([]);
    expect(res.flaggedFunctions).toEqual([]);
  });
});

describe("getCBlocks / getBlockContainingLine / ranges", () => {
  it("encontra blocos top-level por equilíbrio de chavetas", () => {
    const blocks = getCBlocks(SAMPLE_C_CODE);
    expect(blocks).toEqual([
      { start: 2, end: 5 },
      { start: 7, end: 9 },
    ]);
  });

  it("devolve o bloco que contém uma linha", () => {
    expect(getBlockContainingLine(SAMPLE_C_CODE, 3)).toEqual({ start: 2, end: 5 });
    expect(getBlockContainingLine(SAMPLE_C_CODE, 6)).toBeNull();
  });

  it("mergeRanges junta intervalos sobrepostos e adjacentes", () => {
    expect(
      mergeRanges([
        { start: 10, end: 12 },
        { start: 1, end: 3 },
        { start: 4, end: 5 },
      ])
    ).toEqual([
      { start: 1, end: 5 },
      { start: 10, end: 12 },
    ]);
  });

  it("getCDisplayRanges normaliza e funde os ranges das funções suspeitas", () => {
    const ranges = getCDisplayRanges("code", [
      { startLine: 5, endLine: 2 },
      { startLine: 1, endLine: 3 },
    ]);
    expect(ranges).toEqual([{ start: 1, end: 5 }]);
    expect(getCDisplayRanges("code", [])).toBeUndefined();
  });
});

describe("clampFlaggedFunctionsToCode", () => {
  it("remove funções cujo range excede o pseudo-C carregado", () => {
    const cCode = "line1\nline2\nline3";
    const flagged = [
      { name: "fora", startLine: 100, endLine: 200 },
      { name: "dentro", startLine: 2, endLine: 3 },
    ];
    const clamped = clampFlaggedFunctionsToCode(cCode, flagged);
    expect(clamped).toHaveLength(1);
    expect(clamped[0].name).toBe("dentro");
    expect(isFlaggedRangeInCode(3, clamped[0])).toBe(true);
  });
});

describe("getWordStats", () => {
  it("conta menções, infere tipo e funções onde a palavra aparece", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "valor", undefined);
    expect(stats.mentions).toBe(2);
    expect(stats.inferredType).toBe("int");
    expect(stats.functionsCount).toBe(1);
  });

  it("marca funções maliciosas quando o bloco está dentro de um range suspeito", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "read_config", [{ start: 7, end: 9 }]);
    expect(stats.functionsCount).toBe(2);
    expect(stats.maliciousCount).toBe(1);
  });

  it("rejeita palavras que não são identificadores válidos (sem construir RegExp)", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "a+b(", undefined);
    expect(stats).toEqual({ mentions: 0, inferredType: null, functionsCount: 0, maliciousCount: 0 });
  });
});
