import { useCallback, useEffect, useRef } from "react";
import { getT } from "@/i18n";
import { apiFetchJson } from "@/lib/api";

export const POLL_INTERVAL_MS = 1000;
/** ~5 minutos com intervalo de 1s. */
export const POLL_MAX_ATTEMPTS = 300;

export type AnalysisJobSubmitResponse = {
  jobId: string;
  analysisType: string;
  status: string;
};

export type PollOutcome =
  | { kind: "completed"; job: Record<string, unknown> }
  | { kind: "failed"; error: string }
  /** O job continua queued/running após o tempo máximo de espera (não é um erro). */
  | { kind: "still-running"; lastStatus: string };

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal.reason ?? new DOMException(getT("cancelled"), "AbortError"));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    if (signal.aborted) onAbort();
    else signal.addEventListener("abort", onAbort, { once: true });
  });
}

/**
 * Hook para submissão e polling de jobs de análise (`/api/analysis`).
 * Todas as operações partilham um AbortController: iniciar uma nova operação
 * cancela a anterior e o unmount cancela qualquer polling pendente.
 */
export function useAnalysisJob() {
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

  /** Cancela operações anteriores e cria um novo "contexto" cancelável. */
  const beginSession = useCallback((): AbortSignal => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    return controller.signal;
  }, []);

  const submitJob = useCallback(
    async (file: File, mode: string, signal: AbortSignal): Promise<AnalysisJobSubmitResponse> => {
      const formData = new FormData();
      formData.append("file", file);
      return apiFetchJson<AnalysisJobSubmitResponse>(
        `/api/analysis?analysis_type=${encodeURIComponent(mode)}`,
        {
          method: "POST",
          body: formData,
          // O upload pode demorar; cancelamento via signal.
          timeoutMs: 0,
          signal,
        }
      );
    },
    []
  );

  const fetchJob = useCallback(
    async (jobId: string, signal?: AbortSignal): Promise<Record<string, unknown>> => {
      return apiFetchJson<Record<string, unknown>>(
        `/api/analysis/${encodeURIComponent(jobId)}`,
        { signal }
      );
    },
    []
  );

  /**
   * Faz polling do job até concluir, falhar ou esgotar as tentativas.
   * Em vez de lançar erro por timeout, devolve `still-running` para a UI
   * mostrar um aviso informativo.
   */
  const pollJob = useCallback(
    async (
      jobId: string,
      signal: AbortSignal,
      onTick?: (status: string, attempt: number, job?: Record<string, unknown>) => void
    ): Promise<PollOutcome> => {
      let lastStatus = getT("unknownStatus");
      for (let attempt = 1; attempt <= POLL_MAX_ATTEMPTS; attempt++) {
        const job = await fetchJob(jobId, signal);
        lastStatus = typeof job.status === "string" ? job.status : getT("unknownStatus");

        if (lastStatus === "queued" || lastStatus === "running") {
          onTick?.(lastStatus, attempt, job);
          await sleep(POLL_INTERVAL_MS, signal);
          continue;
        }

        if (lastStatus === "failed") {
          const error =
            typeof job.error === "string" && job.error
              ? job.error
              : getT("analysisFailed");
          return { kind: "failed", error };
        }

        return { kind: "completed", job };
      }
      return { kind: "still-running", lastStatus };
    },
    [fetchJob]
  );

  return { beginSession, submitJob, fetchJob, pollJob, cancel };
}
