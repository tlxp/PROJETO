// --- Módulo: mockDemoEnabled.ts ---
// Flag de desenvolvimento para o layout mock (sem backend).

/**
 * Indica se o mock de demonstração está activo.
 *
 * Condições (todas em modo dev — `import.meta.env.DEV`):
 * - `?demo=1` na query string (auto-carrega resultados mock), ou
 * - `VITE_ENABLE_MOCK_DEMO=true` no `.env` (botão «Ver layout de teste»).
 *
 * Em produção devolve sempre false; o chunk `mockDemo.ts` só é importado
 * dinamicamente quando esta função é true (tree-shake em `vite build`).
 */
export function isMockDemoEnabled(search = ""): boolean {
  if (!import.meta.env.DEV) return false;
  const params = new URLSearchParams(search);
  if (params.get("demo") === "1") return true;
  return import.meta.env.VITE_ENABLE_MOCK_DEMO === "true";
}
