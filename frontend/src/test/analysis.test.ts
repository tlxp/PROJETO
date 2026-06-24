// --- Módulo: analysis.test.ts ---
import { describe, it, expect } from "vitest";
import {
  areAnalysisResultsEquivalent,
  buildAnalysisResultFromJob,
  flaggedFunctionsSignature,
  normalizeAnalysisResult,
  resolveFlaggedFunctionId,
  parseReportCategories,
  parseReportChapters,
  parseReportResumoLines,
  formatVmReportForDisplay,
  parseVmScoringFromReport,
  compareAnalysisScores,
  translateVmClassification,
  getCBlocks,
  mergeRanges,
  getBlockContainingLine,
  getCDisplayRanges,
  getWordStats,
  clampFlaggedFunctionsToCode,
  isFlaggedRangeInCode,
  isStaticAnalysisInProgress,
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

// --- Testes: formatVmReportForDisplay ---
describe("formatVmReportForDisplay", () => {
  const SAMPLE_VM_RAW = [
    "===============================================================================",
    "RELATÓRIO DE ANÁLISE COMPORTAMENTAL (VM SANDBOX)",
    "Amostra: C:\\analysis_work\\sample.exe",
    "Hash SHA256: ABC123",
    "Data/Hora: 2025-06-16 12:00:00",
    "===============================================================================",
    "",
    "--- BASELINE (antes da execução) ---",
    "Modo baseline rápido",
    "",
    "--- ALTERAÇÕES EM FICHEIROS ---",
    "Foi criado o ficheiro: C:\\Users\\Public\\evil.dll",
    "Não foram detetadas alterações nos ficheiros nas pastas monitorizadas.",
    "",
    "--- AVALIAÇÃO DE RISCO (SCORING) ---",
    "Score total (bruto): 8/21",
    "Score total (0-100): 38/100",
    "Classificação: suspicious",
    "Nota: amostra de validação conhecida (BenignVmTest)",
    "",
    "===============================================================================",
    "FIM DO RELATÓRIO",
    "===============================================================================",
    "REPORT_END;",
  ].join("\n");

// --- Verifica: converte secções --- ... --- em cabeçalhos ALL-CAPS como o relatório estático ---
  it("converte secções --- ... --- em cabeçalhos ALL-CAPS como o relatório estático", () => {
    const formatted = formatVmReportForDisplay(SAMPLE_VM_RAW);
    expect(formatted).toContain("RESUMO");
    expect(formatted).toContain("INFORMAÇÕES DO FICHEIRO");
    expect(formatted).toContain("SCORE DE RISCO");
    expect(formatted).toContain("BASELINE (ANTES DA EXECUÇÃO)");
    expect(formatted).toContain("ALTERAÇÕES EM FICHEIROS");
    expect(formatted).not.toContain("AVALIAÇÃO DE RISCO (SCORING)");
    expect(formatted).not.toContain("REPORT_END");
    expect(formatted).not.toContain("FIM DO RELAT");
    expect(formatted).not.toMatch(/^---\s/m);
  });

// --- Verifica: transforma deteções em bullets e inclui score na secção SCORE DE RISCO ---
  it("transforma deteções em bullets e inclui score na secção SCORE DE RISCO", () => {
    const formatted = formatVmReportForDisplay(SAMPLE_VM_RAW);
    expect(formatted).toContain("  - Foi criado o ficheiro: C:\\Users\\Public\\evil.dll");
    expect(formatted).toContain("Score: 38/100");
    expect(formatted).toContain("Nível: SUSPEITO");
    expect(formatted).toContain("amostra de validação conhecida (BenignVmTest)");
    expect(formatted).not.toContain("Nota:");
  });

// --- Verifica: ignora secção de scoring duplicada com título corrompido no fim ---
  it("ignora secção de scoring duplicada com título corrompido no fim", () => {
    const raw = [
      ...SAMPLE_VM_RAW.split("\n").slice(0, -5),
      "--- AVALIA\u00C3\u00A7\u00C3\u00A3O DE RISCO (SCORING) ---",
      "Nota: amostra de validação conhecida (BenignVmTest)",
      "REPORT_END;",
    ].join("\n");
    const formatted = formatVmReportForDisplay(raw);
    expect(formatted).toContain("SCORE DE RISCO");
    expect(formatted).toContain("Nível: SUSPEITO");
    expect(formatted).not.toMatch(/AVALIA.{0,4}O DE RISCO \(SCORING\)/i);
    expect(formatted).toContain("amostra de validação conhecida (BenignVmTest)");
  });

// --- Verifica: reformata relatório já normalizado sem perder secções ---
  it("reformata relatório já normalizado sem perder secções", () => {
    const once = formatVmReportForDisplay(SAMPLE_VM_RAW);
    const twice = formatVmReportForDisplay(once);
    expect(twice).toContain("ALTERAÇÕES EM FICHEIROS");
    expect(twice).toContain("BASELINE (ANTES DA EXECUÇÃO)");
    expect(twice).not.toMatch(/AVALIA.{0,4}O DE RISCO \(SCORING\)/i);
  });

// --- Verifica: formata relatório JSON enriquecido da VM ---
  it("formata relatório JSON enriquecido da VM", () => {
    const json = JSON.stringify({
      sample_path: "C:\\sample.exe",
      sample_sha256: "deadbeef",
      scoring: { score: 10, scoreRaw: 2, scoreMax: 21, classification: "benign" },
      summary: { file_changes_count: 0, new_processes_count: 1, registry_changes_count: 0, network_changed: false },
    });
    const formatted = formatVmReportForDisplay(json);
    expect(formatted).toContain("RELATÓRIO DE ANÁLISE COMPORTAMENTAL");
    expect(formatted).toContain("SCORE DE RISCO");
    expect(formatted).toContain("Nível: BENIGNO");
    expect(formatted).toContain("Processos: 1");
    expect(formatted).not.toContain("DETALHES (JSON)");
  });
});

// --- Testes: parseVmScoringFromReport ---
describe("parseVmScoringFromReport", () => {
// --- Verifica: extrai score e classificação do relatório VM ---
  it("extrai score e classificação do relatório VM", () => {
    const vm = parseVmScoringFromReport(
      "Score total (0-100): 43/100\nScore total (bruto): 9/21\nClassificação: benign\nNota: amostra de validação conhecida (BenignVmTest)"
    );
    expect(vm?.score).toBe(43);
    expect(vm?.scoreRaw).toBe(9);
    expect(vm?.scoreMax).toBe(21);
    expect(vm?.classification).toBe("BENIGNO");
    expect(vm?.knownValidationSample).toBe(true);
  });
});

// --- Testes: translateVmClassification ---
describe("translateVmClassification", () => {
// --- Verifica: traduz classificações legadas em inglês ---
  it("traduz classificações legadas em inglês", () => {
    expect(translateVmClassification("suspicious")).toBe("SUSPEITO");
    expect(translateVmClassification("malicious")).toBe("MALICIOSO");
    expect(translateVmClassification("not_executed")).toBe("NÃO EXECUTADO");
  });
});

// --- Testes: compareAnalysisScores ---
describe("compareAnalysisScores", () => {
// --- Verifica: deteta divergência entre estática alta e VM benigna (BenignVmTest) ---
  it("deteta divergência entre estática alta e VM benigna (BenignVmTest)", () => {
    const vm = parseVmScoringFromReport("Score: 43/100\nClassificação: benign\nBenignVmTest");
    const cmp = compareAnalysisScores(69, "ALTO", vm);
    expect(cmp.hasBoth).toBe(true);
    expect(cmp.diverges).toBe(true);
    expect(cmp.summary).toContain("amostra de validação");
  });
});

// --- Testes: parseReportCategories ---
describe("parseReportCategories", () => {
// --- Verifica: extrai categorias com resumo e linhas de ocorrências ---
  it("extrai categorias com resumo e linhas de ocorrências", () => {
    const cats = parseReportCategories(SAMPLE_REPORT);
    expect(cats).toHaveLength(2);
    expect(cats[0].label).toContain("Suspicious Imports");
    expect(cats[0].lineNumbers).toEqual([42, 58]);
    expect(cats[1].label).toContain("Obfuscation");
    expect(cats[1].lineNumbers).toEqual([27]);
  });

// --- Verifica: devolve lista vazia para relatório sem categorias ---
  it("devolve lista vazia para relatório sem categorias", () => {
    expect(parseReportCategories("sem nada relevante")).toEqual([]);
  });
});

// --- Testes: parseReportChapters ---
describe("parseReportChapters", () => {
// --- Verifica: extrai cabeçalhos ALL-CAPS ignorando separadores ---
  it("extrai cabeçalhos ALL-CAPS ignorando separadores", () => {
    const chapters = parseReportChapters(SAMPLE_REPORT);
    const labels = chapters.map((c) => c.label);
    expect(labels).toContain("SCORE DE RISCO GLOBAL");
    expect(labels).toContain("DETALHE DAS CATEGORIAS");
    expect(labels).not.toContain("=============================");
  });
});

// --- Testes: parseReportResumoLines ---
describe("parseReportResumoLines", () => {
// --- Verifica: extrai linhas da secção RESUMO até ao próximo cabeçalho ---
  it("extrai linhas da secção RESUMO até ao próximo cabeçalho", () => {
    const report = ["INTRO", "RESUMO", "Linha A", "Linha B", "SCORE DE RISCO:", "x"].join("\n");
    expect(parseReportResumoLines(report)).toEqual(["Linha A", "Linha B"]);
  });

// --- Verifica: devolve null se não houver RESUMO ---
  it("devolve null se não houver RESUMO", () => {
    expect(parseReportResumoLines(SAMPLE_REPORT)).toBeNull();
  });
});

// --- Testes: buildAnalysisResultFromJob ---
describe("buildAnalysisResultFromJob", () => {
// --- Verifica: usa staticResult quando presente (incluindo flaggedFunctions) ---
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

// --- Verifica: aceita staticResult serializado como string JSON ---
  it("aceita staticResult serializado como string JSON", () => {
    const job = { staticResult: JSON.stringify({ report: "R", riskScore: 10 }) };
    const res = buildAnalysisResultFromJob(job, "fallback.bin");
    expect(res?.report).toBe("R");
    expect(res?.riskScore).toBe(10);
    expect(res?.fileName).toBe("fallback.bin");
  });

// --- Verifica: constrói resultado a partir de dynamicResult quando não há staticResult ---
  it("constrói resultado a partir de dynamicResult quando não há staticResult", () => {
    const job = { dynamicResult: { dynamicSummary: "ok", dynamicReport: { a: 1 } } };
    const res = buildAnalysisResultFromJob(job, "x.exe");
    expect(res?.dynamicSummary).toBe("ok");
    expect(res?.vmReport).toContain('"a": 1');
    expect(res?.report).toBe("");
    expect(res?.cCode).toBe("");
  });

// --- Verifica: usa campos no root como fallback (payloads antigos) ---
  it("usa campos no root como fallback (payloads antigos)", () => {
    const res = buildAnalysisResultFromJob({ report: "root", cCode: "c" });
    expect(res?.report).toBe("root");
    expect(res?.cCode).toBe("c");
  });

// --- Verifica: devolve null para payloads sem resultado ---
  it("devolve null para payloads sem resultado", () => {
    expect(buildAnalysisResultFromJob(null)).toBeNull();
    expect(buildAnalysisResultFromJob({ status: "running" })).toBeNull();
  });
});

// --- Testes: isStaticAnalysisInProgress ---
describe("isStaticAnalysisInProgress", () => {
// --- Verifica: detecta staticPending no resultado do job ---
  it("detecta staticPending no resultado do job", () => {
    expect(
      isStaticAnalysisInProgress(
        { report: "", cCode: "", ilCode: "", fileName: "x", riskScore: 0, riskLevel: "", staticPending: true, vmReport: "vm" },
        false
      )
    ).toBe(true);
  });

// --- Verifica: mantém overlay enquanto isAnalyzing e faltam report/cCode mesmo com vmReport ---
  it("mantém overlay enquanto isAnalyzing e faltam report/cCode mesmo com vmReport", () => {
    expect(
      isStaticAnalysisInProgress(
        { report: "", cCode: "", ilCode: "", fileName: "x", riskScore: 0, riskLevel: "", vmReport: "relatório VM" },
        true
      )
    ).toBe(true);
  });

// --- Verifica: liberta quando estática completa ---
  it("liberta quando estática completa", () => {
    expect(
      isStaticAnalysisInProgress(
        { report: "R", cCode: "void f(){}", ilCode: "", fileName: "x", riskScore: 0, riskLevel: "", vmReport: "vm" },
        false
      )
    ).toBe(false);
  });
});

// --- Testes: normalizeAnalysisResult ---
describe("normalizeAnalysisResult", () => {
// --- Verifica: aplica defaults seguros a campos em falta ou de tipo errado ---
  it("aplica defaults seguros a campos em falta ou de tipo errado", () => {
    const res = normalizeAnalysisResult({ riskScore: "92", report: 5 }, "file.exe");
    expect(res.report).toBe("");
    expect(res.riskScore).toBe(0);
    expect(res.fileName).toBe("file.exe");
    expect(res.flaggedIndicators).toEqual([]);
    expect(res.flaggedFunctions).toEqual([]);
  });
});

// --- Testes: getCBlocks / getBlockContainingLine / ranges ---
describe("getCBlocks / getBlockContainingLine / ranges", () => {
// --- Verifica: encontra blocos top-level por equilíbrio de chavetas ---
  it("encontra blocos top-level por equilíbrio de chavetas", () => {
    const blocks = getCBlocks(SAMPLE_C_CODE);
    expect(blocks).toEqual([
      { start: 2, end: 5 },
      { start: 7, end: 9 },
    ]);
  });

// --- Verifica: devolve o bloco que contém uma linha ---
  it("devolve o bloco que contém uma linha", () => {
    expect(getBlockContainingLine(SAMPLE_C_CODE, 3)).toEqual({ start: 2, end: 5 });
    expect(getBlockContainingLine(SAMPLE_C_CODE, 6)).toBeNull();
  });

// --- Verifica: mergeRanges junta intervalos sobrepostos e adjacentes ---
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

// --- Verifica: getCDisplayRanges normaliza e funde os ranges das funções suspeitas ---
  it("getCDisplayRanges normaliza e funde os ranges das funções suspeitas", () => {
    const ranges = getCDisplayRanges("code", [
      { startLine: 5, endLine: 2 },
      { startLine: 1, endLine: 3 },
    ]);
    expect(ranges).toEqual([{ start: 1, end: 5 }]);
    expect(getCDisplayRanges("code", [])).toBeUndefined();
  });
});

// --- Testes: clampFlaggedFunctionsToCode ---
describe("clampFlaggedFunctionsToCode", () => {
// --- Verifica: remove funções cujo range excede o pseudo-C carregado ---
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

// --- Testes: getWordStats ---
describe("getWordStats", () => {
// --- Verifica: conta menções, infere tipo e funções onde a palavra aparece ---
  it("conta menções, infere tipo e funções onde a palavra aparece", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "valor", undefined);
    expect(stats.mentions).toBe(2);
    expect(stats.inferredType).toBe("int");
    expect(stats.functionsCount).toBe(1);
  });

// --- Verifica: marca funções maliciosas quando o bloco está dentro de um range suspeito ---
  it("marca funções maliciosas quando o bloco está dentro de um range suspeito", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "read_config", [{ start: 7, end: 9 }]);
    expect(stats.functionsCount).toBe(2);
    expect(stats.maliciousCount).toBe(1);
  });

// --- Verifica: rejeita palavras que não são identificadores válidos (sem construir RegExp) ---
  it("rejeita palavras que não são identificadores válidos (sem construir RegExp)", () => {
    const stats = getWordStats(SAMPLE_C_CODE, "a+b(", undefined);
    expect(stats).toEqual({ mentions: 0, inferredType: null, functionsCount: 0, maliciousCount: 0 });
  });
});

// --- Testes: resolveFlaggedFunctionId / flaggedFunctionsSignature ---
describe("resolveFlaggedFunctionId / flaggedFunctionsSignature", () => {
// --- Verifica: gera ID estável com ou sem campo id ---
  it("gera ID estável com ou sem campo id", () => {
    expect(resolveFlaggedFunctionId({ name: "foo", startLine: 10, endLine: 20 })).toBe("foo:10-20");
    expect(resolveFlaggedFunctionId({ name: "foo", id: "FUN_1", startLine: 10, endLine: 20 })).toBe("FUN_1");
  });

// --- Verifica: assinatura ignora ordem de referência do array ---
  it("assinatura ignora ordem de referência do array", () => {
    const a = [{ name: "a", startLine: 1, endLine: 2 }, { name: "b", startLine: 3, endLine: 4 }];
    const b = [...a];
    expect(flaggedFunctionsSignature(a)).toBe(flaggedFunctionsSignature(b));
  });
});

// --- Testes: areAnalysisResultsEquivalent ---
describe("areAnalysisResultsEquivalent", () => {
// --- Verifica: considera equivalentes resultados com mesmo conteúdo mas referências diferentes ---
  it("considera equivalentes resultados com mesmo conteúdo mas referências diferentes", () => {
    const base = normalizeAnalysisResult({
      report: "r",
      cCode: "c",
      ilCode: "il",
      flaggedFunctions: [{ name: "f", startLine: 1, endLine: 2 }],
    });
    const copy = { ...base, flaggedFunctions: [...(base.flaggedFunctions ?? [])] };
    expect(areAnalysisResultsEquivalent(base, copy)).toBe(true);
  });

// --- Verifica: deteta alterações relevantes ---
  it("deteta alterações relevantes", () => {
    const a = normalizeAnalysisResult({ report: "r", cCode: "c" });
    const b = normalizeAnalysisResult({ report: "r2", cCode: "c" });
    expect(areAnalysisResultsEquivalent(a, b)).toBe(false);
  });
});
