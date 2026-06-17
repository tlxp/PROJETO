import { test, expect } from "@playwright/test";

test.describe("Página inicial", () => {
  test("carrega a zona de upload", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Analise o seu código" })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText("Arraste o ficheiro para aqui")).toBeVisible();
  });

  test("rejeita extensão inválida via input de ficheiro", async ({ page }) => {
    await page.goto("/");
    const input = page.locator('input[type="file"]');
    await input.setInputFiles({
      name: "notas.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("hello"),
    });
    // Toast Sonner — texto pode variar; ficheiro inválido não deve aparecer como selecionado
    await expect(page.getByText("notas.txt")).not.toBeVisible({ timeout: 5_000 });
  });
});

test.describe("Fluxo de análise (API mockada)", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/api/health", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ status: "ok" }),
      });
    });

    await page.route("**/api/analyze_stream", async (route) => {
      const lines = [
        JSON.stringify({ type: "log", message: "Início da análise" }),
        JSON.stringify({
          type: "result",
          report: "# Relatório de teste",
          cCode: "void main() {}",
          ilCode: "# IL mock",
          fileName: "sample.exe",
          riskScore: 42,
          riskLevel: "MEDIUM",
          flaggedIndicators: [],
          flaggedFunctions: [],
        }),
      ].join("\n");
      await route.fulfill({
        status: 200,
        contentType: "application/x-ndjson",
        body: lines,
      });
    });

    await page.route("**/api/analysis/upload_static", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          jobId: "00000000-0000-4000-8000-000000000001",
          analysisType: "static",
          status: "completed",
        }),
      });
    });
  });

  test("upload de .exe mostra resultados após streaming", async ({ page }) => {
    await page.goto("/");
    const input = page.locator('input[type="file"]');
    await input.setInputFiles({
      name: "sample.exe",
      mimeType: "application/octet-stream",
      buffer: Buffer.from("MZfake"),
    });

    await expect(page.getByText(/sample\.exe/i)).toBeVisible({ timeout: 10_000 });
    await page.getByRole("button", { name: "Executar Análise" }).click();
    await expect(page.getByText("Estática: 42/100 (MEDIUM)")).toBeVisible({ timeout: 30_000 });
  });
});
