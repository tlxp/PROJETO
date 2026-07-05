// --- Módulo: useSandboxHealth.ts ---
// Consulta /api/health para saber se a sandbox real está configurada.

import { useEffect, useState } from "react";
import { isVmDriverStub } from "@/lib/analysis/stubDetection";
import { fetchSandboxHealth } from "@/lib/sandboxHealth";

export function useSandboxHealth() {
  const [vmDriver, setVmDriver] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void fetchSandboxHealth()
      .then((health) => {
        if (!cancelled) {
          setVmDriver(typeof health.vmDriver === "string" ? health.vmDriver : "unset");
        }
      })
      .catch(() => {
        if (!cancelled) setVmDriver(null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return {
    vmDriver,
    isStubDriver: isVmDriverStub(vmDriver),
    isDriverUnknown: vmDriver == null,
  };
}
