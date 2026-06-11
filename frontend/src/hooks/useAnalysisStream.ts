import { useCallback, useEffect, useRef } from "react";
import { apiFetch, readErrorDetail } from "@/lib/api";
import { asRecord, normalizeAnalysisResult, type AnalysisResult } from "@/lib/analysis";

/** Prefixo das linhas de log com progresso do Ghidra (streaming). */
export const GHIDRA_PROGRESS_PREFIX = "[GHIDRA_PROGRESS]";

/** Limite de segurança do buffer NDJSON (linhas individuais nunca devem chegar perto disto). */
export const MAX_STREAM_BUFFER_BYTES = 10 * 1024 * 1024;

export type AnalysisStreamCallbacks = {
  onLog: (message: string) => void;
  onGhidraProgress: (percent: number) => void;
  onError: (message: string) => void;
  onResult: (result: AnalysisResult) => void;
};

/**
 * Hook para a análise estática por streaming NDJSON (`/api/analyze_stream`).
 * Gere o cancelamento via AbortController (nova execução cancela a anterior;
 * o unmount cancela qualquer streaming pendente).
 */
export function useAnalysisStream() {
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    return () => {
      abortRef.current?.abort();
      abortRef.current = null;
    };
  }, []);

  const cancel = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
  }, []);

  /**
   * Executa o streaming e devolve o último resultado recebido (ou null).
   * Lança AbortError/TimeoutError (DOMException) quando cancelado.
   */
  const run = useCallback(
    async (file: File, callbacks: AnalysisStreamCallbacks): Promise<AnalysisResult | null> => {
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;

      const formData = new FormData();
      formData.append("file", file);

      const res = await apiFetch("/api/analyze_stream", {
        method: "POST",
        body: formData,
        // A análise pode demorar minutos; o cancelamento é feito pelo AbortController.
        timeoutMs: 0,
        signal: controller.signal,
      });
      if (!res.ok || !res.body) {
        const text = await readErrorDetail(res, res.statusText);
        throw new Error(text || res.statusText);
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder("utf-8");
      let buffer = "";
      let streamResult: AnalysisResult | null = null;

      const handleLine = (raw: string) => {
        const line = raw.trim();
        if (!line) return;
        let obj: unknown;
        try {
          obj = JSON.parse(line);
        } catch {
          return;
        }
        const rec = asRecord(obj);
        if (!rec) return;

        if (rec.type === "log" && typeof rec.message === "string") {
          const msg = rec.message;
          if (msg.startsWith(GHIDRA_PROGRESS_PREFIX)) {
            const rest = msg.slice(GHIDRA_PROGRESS_PREFIX.length).trim();
            const numeric = parseFloat(rest.replace("%", ""));
            if (!Number.isNaN(numeric)) {
              callbacks.onGhidraProgress(Math.max(0, Math.min(100, numeric)));
            }
          } else {
            callbacks.onLog(msg);
          }
        } else if (rec.type === "error" && typeof rec.message === "string") {
          callbacks.onError(rec.message);
        } else if (rec.type === "result") {
          const data = normalizeAnalysisResult(rec, file.name);
          streamResult = data;
          callbacks.onResult(data);
        }
      };

      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          if (buffer.length > MAX_STREAM_BUFFER_BYTES) {
            controller.abort();
            throw new Error(
              "Resposta de streaming excedeu o limite de buffer (10 MB); análise abortada."
            );
          }
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const raw of lines) handleLine(raw);
        }
        // Última linha sem newline final (se existir).
        if (buffer.trim()) handleLine(buffer);
      } finally {
        reader.releaseLock();
      }

      return streamResult;
    },
    []
  );

  return { run, cancel };
}
