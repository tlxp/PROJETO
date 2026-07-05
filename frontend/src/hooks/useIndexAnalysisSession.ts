// --- Módulo: useIndexAnalysisSession.ts ---
// Orquestração de análise na página Index (upload, stream estático, jobs Caminho A).

import { useCallback, useEffect, useRef, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import { ApiError, isAbortError } from "@/lib/api";
import { getT } from "@/i18n";
import {
  areAnalysisResultsEquivalent,
  buildAnalysisResultFromJob,
  publishStaticAnalysisResult,
  type AnalysisMode,
  type AnalysisResult,
} from "@/lib/analysis";
import { useAnalysisJob } from "@/hooks/useAnalysisJob";
import { useAnalysisStream } from "@/hooks/useAnalysisStream";
import { useSandboxHealth } from "@/hooks/useSandboxHealth";
import { ROUTES } from "@/routes";
import type { StillRunningJob } from "@/pages/Index/UploadView";
import { isMockDemoEnabled } from "@/lib/mockDemoEnabled";

// --- Hook ---
export function useIndexAnalysisSession() {
  const location = useLocation();
  const navigate = useNavigate();
  const { jobId: jobIdFromPath } = useParams<{ jobId?: string }>();

  const [file, setFile] = useState<File | null>(null);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [showResults, setShowResults] = useState(false);
  const [analysisResult, setAnalysisResult] = useState<AnalysisResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [analysisLogs, setAnalysisLogs] = useState<string[]>([]);
  const [ghidraProgress, setGhidraProgress] = useState<number | null>(null);
  const [analysisMode, setAnalysisMode] = useState<AnalysisMode>("static");
  const [currentJobId, setCurrentJobId] = useState<string | null>(null);
  const [stillRunningJob, setStillRunningJob] = useState<StillRunningJob | null>(null);
  const [isMockDemo, setIsMockDemo] = useState(false);
  const [stubConfirmOpen, setStubConfirmOpen] = useState(false);

  const stream = useAnalysisStream();
  const { beginSession, submitJob, pollJob, fetchJob, cancel: cancelJob } = useAnalysisJob();
  const { isStubDriver } = useSandboxHealth();
  const analyzeRunRef = useRef(0);

  const handleFileLoaded = useCallback((f: File) => {
    setFile(f);
    setShowResults(false);
    setAnalysisResult(null);
    setError(null);
    setAnalysisLogs([]);
    setGhidraProgress(null);
    setStillRunningJob(null);
    setIsMockDemo(false);
  }, []);

  const handleClear = useCallback(() => {
    analyzeRunRef.current += 1;
    stream.cancel();
    cancelJob();
    setFile(null);
    setShowResults(false);
    setAnalysisResult(null);
    setError(null);
    setAnalysisLogs([]);
    setGhidraProgress(null);
    setIsAnalyzing(false);
    setStillRunningJob(null);
    setCurrentJobId(null);
    setIsMockDemo(false);
    navigate(ROUTES.home, { replace: true });
  }, [navigate, stream, cancelJob]);

  // --- Carrega job externo a partir de URL (?jobId= ou /analysis/:jobId) ---
  useEffect(() => {
    const params = new URLSearchParams(location.search ?? "");
    const jobIdFromQuery = params.get("jobId");
    const jobId = jobIdFromPath ?? jobIdFromQuery;
    if (!jobId) return;
    if (jobId === currentJobId) return;

    let cancelled = false;
    const signal = beginSession();
    const runId = ++analyzeRunRef.current;

    const loadExternalJob = async () => {
      setShowResults(true);
      setIsAnalyzing(true);
      setError(null);
      setStillRunningJob(null);
      setIsMockDemo(false);
      setAnalysisLogs([`A carregar resultados externos para jobId=${jobId}...`]);

      try {
        if (!cancelled && !jobIdFromPath && jobIdFromQuery) {
          navigate(ROUTES.analysis(jobId), { replace: true });
        }

        const outcome = await pollJob(jobId, signal, (status, attempt, partialJob) => {
          if (!cancelled && partialJob) {
            const partial = buildAnalysisResultFromJob(
              partialJob,
              typeof partialJob.fileName === "string" ? partialJob.fileName : undefined
            );
            if (partial) {
              setAnalysisResult(partial);
              setShowResults(true);
            }
          }
          if (!cancelled && (attempt === 1 || attempt % 10 === 0)) {
            setAnalysisLogs((prev) => [
              ...prev,
              `Job externo ainda em processamento (estado atual: ${status}, tentativa ${attempt}).`,
            ]);
          }
        });
        if (cancelled) return;

        if (outcome.kind === "failed") {
          setError(outcome.error);
          return;
        }
        if (outcome.kind === "still-running") {
          setStillRunningJob({ jobId, lastStatus: outcome.lastStatus });
          return;
        }

        const root = outcome.job;
        const chosen = buildAnalysisResultFromJob(
          root,
          typeof root.fileName === "string" ? root.fileName : undefined
        );
        if (!chosen) {
          setError(getT("noExternalResult"));
          return;
        }

        setAnalysisResult(chosen);
        setShowResults(true);
        setCurrentJobId(jobId);
      } catch (e) {
        if (cancelled || isAbortError(e)) return;
        setError(e instanceof Error ? e.message : getT("loadExternalError"));
      } finally {
        if (!cancelled && analyzeRunRef.current === runId) {
          setIsAnalyzing(false);
        }
      }
    };

    void loadExternalJob();
    return () => {
      cancelled = true;
    };
  }, [location.search, currentJobId, jobIdFromPath, navigate, beginSession, pollJob]);

  // --- Polling leve para atualizar resultados enquanto o job evolui ---
  useEffect(() => {
    if (!currentJobId || !showResults) return;

    let cancelled = false;
    const intervalId = window.setInterval(async () => {
      if (cancelled) return;
      try {
        const job = await fetchJob(currentJobId);
        if (cancelled) return;
        const jobStatus = typeof job.status === "string" ? job.status : "";
        const updated = buildAnalysisResultFromJob(
          job,
          typeof job.fileName === "string" ? job.fileName : undefined
        );
        if (updated) {
          setAnalysisResult((prev) =>
            prev && areAnalysisResultsEquivalent(prev, updated) ? prev : updated
          );
          const stillPending = !!(updated.staticPending || updated.dynamicPending);
          const statusActive = jobStatus === "running" || jobStatus === "queued";
          setIsAnalyzing(stillPending || statusActive);
        }
      } catch {
        /* ignorar erros transitórios de polling */
      }
    }, 1000);

    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
    };
  }, [currentJobId, showResults, fetchJob]);

  const mockDemoAutoLoadedRef = useRef(false);
  useEffect(() => {
    if (mockDemoAutoLoadedRef.current) return;
    const params = new URLSearchParams(location.search ?? "");
    if (!import.meta.env.DEV || params.get("demo") !== "1") return;
    mockDemoAutoLoadedRef.current = true;

    void (async () => {
      const { MOCK_DEMO_RESULT } = await import("@/pages/Index/mockDemo");
      setFile(null);
      setAnalysisResult(MOCK_DEMO_RESULT);
      setShowResults(true);
      setError(null);
      setIsMockDemo(true);
    })();
  }, [location.search]);

  const loadMockDemo = useCallback(async () => {
    if (!isMockDemoEnabled(location.search)) return;
    const { MOCK_DEMO_RESULT } = await import("@/pages/Index/mockDemo");
    setFile(null);
    setAnalysisResult(MOCK_DEMO_RESULT);
    setShowResults(true);
    setError(null);
    setIsMockDemo(true);
  }, [location.search]);

  const finishJobOutcome = useCallback(
    (jobId: string, job: Record<string, unknown>, fallbackFileName?: string) => {
      const chosen = buildAnalysisResultFromJob(job, fallbackFileName);
      if (!chosen) {
        throw new Error(getT("noAnalysisResult"));
      }
      setCurrentJobId(jobId);
      navigate(ROUTES.analysis(jobId), { replace: false });
      setAnalysisResult(chosen);
      setShowResults(true);
    },
    [navigate]
  );

  // --- Estática: stream; dinâmica/ambas: job Caminho A (POST /api/analysis) ---
  const runAnalyze = useCallback(
    async (modeOverride?: AnalysisMode) => {
      if (!file) return;
      const mode = modeOverride ?? analysisMode;
      const runId = ++analyzeRunRef.current;
      const isCurrent = () => analyzeRunRef.current === runId;
      setIsMockDemo(false);
      setIsAnalyzing(true);
      setError(null);
      setAnalysisLogs([]);
      setGhidraProgress(null);
      setStillRunningJob(null);

      try {
        if (mode === "static") {
          const streamResult = await stream.run(file, {
            onLog: (msg) => setAnalysisLogs((prev) => [...prev, msg]),
            onGhidraProgress: (pct) => setGhidraProgress(pct),
            onError: (msg) => setError(msg),
            onResult: (data) => {
              setAnalysisResult(data);
              setShowResults(true);
            },
          });

          if (streamResult && isCurrent()) {
            try {
              const jobId = await publishStaticAnalysisResult(streamResult);
              if (!isCurrent()) return;
              setCurrentJobId(jobId);
              navigate(ROUTES.analysis(jobId), { replace: false });
              setAnalysisLogs((prev) => [...prev, `Resultado registado no backend: ${jobId}`]);
            } catch (e) {
              if (isAbortError(e)) return;
              const message =
                e instanceof Error ? e.message : getT("staticRegisterFailed");
              setAnalysisLogs((prev) => [...prev, message]);
            }
          }
          return;
        }

        const signal = beginSession();
        const submitData = await submitJob(file, mode, signal);
        if (!isCurrent()) return;
        setAnalysisLogs((prev) => [...prev, `Job criado (${mode}): ${submitData.jobId}`]);

        const outcome = await pollJob(submitData.jobId, signal, (status, attempt, partialJob) => {
          if (isCurrent() && partialJob) {
            const partial = buildAnalysisResultFromJob(
              partialJob,
              typeof partialJob.fileName === "string" ? partialJob.fileName : file.name
            );
            if (partial) {
              setAnalysisResult(partial);
              setShowResults(true);
            }
          }
          if (isCurrent() && (attempt === 1 || attempt % 10 === 0)) {
            setAnalysisLogs((prev) => [...prev, `Estado do job: ${status}`]);
          }
        });
        if (!isCurrent()) return;

        if (outcome.kind === "failed") {
          throw new Error(outcome.error);
        }
        if (outcome.kind === "still-running") {
          setStillRunningJob({ jobId: submitData.jobId, lastStatus: outcome.lastStatus });
          setCurrentJobId(submitData.jobId);
          navigate(ROUTES.analysis(submitData.jobId), { replace: false });
          return;
        }

        finishJobOutcome(submitData.jobId, outcome.job, file.name);
      } catch (e) {
        if (!isCurrent() || isAbortError(e)) return;
        if (e instanceof ApiError && e.status === 404) {
          setError(getT("jobNotFound"));
        } else {
          setError(e instanceof Error ? e.message : getT("analyzeFileError"));
        }
      } finally {
        if (isCurrent()) {
          setIsAnalyzing(false);
        }
      }
    },
    [file, analysisMode, stream, beginSession, submitJob, pollJob, navigate, finishJobOutcome]
  );

  const handleAnalyze = useCallback(() => {
    if (!file) return;
    if ((analysisMode === "dynamic" || analysisMode === "both") && isStubDriver) {
      setStubConfirmOpen(true);
      return;
    }
    void runAnalyze();
  }, [file, analysisMode, isStubDriver, runAnalyze]);

  const handleStubConfirmContinue = useCallback(() => {
    setStubConfirmOpen(false);
    void runAnalyze();
  }, [runAnalyze]);

  const handleStubConfirmStaticOnly = useCallback(() => {
    setStubConfirmOpen(false);
    setAnalysisMode("static");
    void runAnalyze("static");
  }, [runAnalyze]);

  return {
    file,
    isAnalyzing,
    showResults,
    analysisResult,
    error,
    analysisLogs,
    ghidraProgress,
    analysisMode,
    setAnalysisMode,
    currentJobId,
    stillRunningJob,
    isMockDemo,
    isStubDriver,
    stubConfirmOpen,
    setStubConfirmOpen,
    handleFileLoaded,
    handleClear,
    handleAnalyze,
    handleStubConfirmContinue,
    handleStubConfirmStaticOnly,
    loadMockDemo,
  };
}
