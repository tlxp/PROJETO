/**
 * Camada única de acesso à API do backend (RAT Analyzer).
 * Centraliza o base URL, helpers de fetch com timeout/AbortController
 * e o tratamento de mensagens de erro do FastAPI ({ detail: ... }).
 */

export const API_BASE: string = import.meta.env.VITE_API_URL || "http://localhost:8000";

/** Token opcional (env VITE_API_TOKEN) quando o backend exige RATANALYZER_API_TOKEN. */
export const API_TOKEN: string | undefined = import.meta.env.VITE_API_TOKEN || undefined;

/** Timeout por defeito para pedidos "curtos" (status, artefactos, etc.). */
export const DEFAULT_TIMEOUT_MS = 30_000;

export type ErrorResponse = { detail?: unknown };
export type ValidationDetailItem = { msg?: unknown };

export class ApiError extends Error {
  status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

export function isAbortError(e: unknown): boolean {
  return e instanceof DOMException && (e.name === "AbortError" || e.name === "TimeoutError");
}

export function stringifyDetail(detail: unknown): string {
  if (detail == null) return "";
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((d) => {
        if (typeof d === "string") return d;
        if (d && typeof d === "object" && "msg" in d) {
          const msg = (d as ValidationDetailItem).msg;
          return typeof msg === "string" ? msg : JSON.stringify(msg);
        }
        return JSON.stringify(d);
      })
      .join(", ");
  }
  try {
    return JSON.stringify(detail);
  } catch {
    return String(detail);
  }
}

export function readErrorDetail(res: Response, fallbackText: string): Promise<string> {
  return res
    .json()
    .catch(() => ({ detail: fallbackText }) satisfies ErrorResponse)
    .then((msg: ErrorResponse) => stringifyDetail(msg?.detail) || fallbackText);
}

export function apiUrl(path: string): string {
  return `${API_BASE}${path.startsWith("/") ? path : `/${path}`}`;
}

export type ApiFetchOptions = Omit<RequestInit, "signal"> & {
  /** Timeout em ms; 0 desativa o timeout (ex.: uploads/streaming longos). */
  timeoutMs?: number;
  signal?: AbortSignal | null;
};

/**
 * `fetch` contra a API com timeout via AbortController.
 * Um `signal` externo (cancelamento do chamador) é combinado com o timeout interno.
 */
export async function apiFetch(path: string, options: ApiFetchOptions = {}): Promise<Response> {
  const { timeoutMs = DEFAULT_TIMEOUT_MS, signal, ...init } = options;
  const controller = new AbortController();

  const timer =
    timeoutMs > 0
      ? setTimeout(
          () => controller.abort(new DOMException("Timeout ao contactar a API.", "TimeoutError")),
          timeoutMs
        )
      : null;

  const onOuterAbort = () => controller.abort(signal?.reason);
  if (signal) {
    if (signal.aborted) controller.abort(signal.reason);
    else signal.addEventListener("abort", onOuterAbort, { once: true });
  }

  const headers = new Headers(init.headers);
  if (API_TOKEN && !headers.has("X-API-Token")) {
    headers.set("X-API-Token", API_TOKEN);
  }

  try {
    return await fetch(apiUrl(path), { ...init, headers, signal: controller.signal });
  } finally {
    if (timer != null) clearTimeout(timer);
    signal?.removeEventListener("abort", onOuterAbort);
  }
}

/** `apiFetch` + validação de status + parse de JSON, lançando `ApiError` com mensagem legível. */
export async function apiFetchJson<T>(path: string, options: ApiFetchOptions = {}): Promise<T> {
  const res = await apiFetch(path, options);
  if (!res.ok) {
    const text = await readErrorDetail(res, res.statusText);
    throw new ApiError(text || res.statusText, res.status);
  }
  return (await res.json()) as T;
}
