// --- Módulo: sandboxHealth.ts ---
// Estado da sandbox exposto pelo endpoint /api/health.

import { apiFetchJson } from "./api";

export type HealthResponse = {
  status?: string;
  vmDriver?: string;
};

export async function fetchSandboxHealth(): Promise<HealthResponse> {
  return apiFetchJson<HealthResponse>("/api/health");
}
