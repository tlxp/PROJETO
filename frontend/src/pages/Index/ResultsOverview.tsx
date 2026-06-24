// --- Módulo: ResultsOverview.tsx ---
import React from "react";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import {
  compareAnalysisScores,
  isVmClassificationBenign,
  parseVmScoringFromReport,
  translateVmClassification,
  type AnalysisResult,
  type ReportCategory,
} from "@/lib/analysis";

type ResultsOverviewProps = {
  result: AnalysisResult;
  reportCategories: ReportCategory[];
  reportResumoLines: string[] | null;
  overviewCategoryIndex: number;
  onChangeCategoryIndex: (updater: (prev: number) => number) => void;
  hasJobId: boolean;
};

function scoreToneClass(score: number, isBenignLabel = false): string {
  if (isBenignLabel) return "text-primary";
  if (score >= 70) return "text-destructive";
  if (score >= 40) return "text-code-string";
  return "text-primary";
}

// --- Overview da análise e categorias navegáveis do relatório ---
const ResultsOverview: React.FC<ResultsOverviewProps> = ({
  result,
  reportCategories,
  reportResumoLines,
  overviewCategoryIndex,
  onChangeCategoryIndex,
  hasJobId,
}) => {
  const vmScoring = parseVmScoringFromReport(result.vmReport);
  const hasStaticScore = result.riskScore > 0 || !!result.riskLevel?.trim();
  const hasVmScore = vmScoring != null;
  const scoreCompare = compareAnalysisScores(result.riskScore, result.riskLevel ?? "", vmScoring);

  if (reportCategories.length === 0 && !hasStaticScore && !hasVmScore) return null;

  return (
    <div className="grid gap-3 md:grid-cols-4 items-stretch text-[11px] font-mono text-muted-foreground">
      <div className="md:col-span-2 rounded-lg border border-border bg-card/70 px-3 py-2">
        {scoreCompare.hasBoth ? (
          <div className="space-y-1.5">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div className="rounded border border-border/60 bg-background/40 px-2.5 py-2">
                <div className="text-[10px] text-muted-foreground">Estática</div>
                <div className={`text-sm font-semibold ${scoreToneClass(result.riskScore)}`}>
                  {result.riskScore}/100
                  {result.riskLevel ? ` · ${result.riskLevel.toUpperCase()}` : ""}
                </div>
              </div>
              <div className="rounded border border-border/60 bg-background/40 px-2.5 py-2">
                <div className="text-[10px] text-muted-foreground">VM</div>
                <div
                  className={`text-sm font-semibold ${scoreToneClass(
                    vmScoring?.score ?? 0,
                    isVmClassificationBenign(vmScoring?.classification)
                  )}`}
                >
                  {vmScoring?.score != null ? `${vmScoring.score}/100` : "—"}
                  {vmScoring?.classification
                    ? ` · ${translateVmClassification(vmScoring.classification)}`
                    : ""}
                </div>
              </div>
            </div>
            {scoreCompare.summary && (
              <p className="text-[10px] text-muted-foreground">{scoreCompare.summary}</p>
            )}
          </div>
        ) : (
          <div className="flex flex-wrap items-center gap-2 text-foreground">
            {hasStaticScore && (
              <span className={`text-xs font-semibold ${scoreToneClass(result.riskScore)}`}>
                Estática: {result.riskScore}/100
                {result.riskLevel && ` (${result.riskLevel.toUpperCase()})`}
              </span>
            )}
            {hasVmScore && (
              <span
                className={`text-xs font-semibold ${scoreToneClass(
                  vmScoring?.score ?? 0,
                  isVmClassificationBenign(vmScoring?.classification)
                )}`}
              >
                VM: {vmScoring?.score != null ? `${vmScoring.score}/100` : "—"}
                {vmScoring?.classification
                  ? ` (${translateVmClassification(vmScoring.classification)})`
                  : ""}
              </span>
            )}
          </div>
        )}

        {result.flaggedIndicators && result.flaggedIndicators.length > 0 && (
          <div className="mt-1.5">
            <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] text-primary">
              {result.flaggedIndicators.length} flags
            </span>
          </div>
        )}
        {(result.obfuscatedSnippetsFile || result.obfuscatedSnippetsDeobfuscatedFile) && !hasJobId && (
          <div className="mt-1.5 text-[10px] text-muted-foreground">
            Trechos obfuscados: secção DEOBFUSCAÇÃO do relatório.
          </div>
        )}
      </div>

      {reportCategories.length > 0 && (
        <div className="md:col-span-2 h-full flex flex-col">
          <div className="flex items-center justify-center gap-1 mb-1">
            <button
              type="button"
              onClick={() =>
                onChangeCategoryIndex((prev) =>
                  (prev - 1 + reportCategories.length) % reportCategories.length
                )
              }
              className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
              aria-label="Categorias anteriores"
              disabled={reportCategories.length <= 1}
            >
              <ChevronLeft className="h-3 w-3" />
            </button>
            <span className="text-[10px] text-muted-foreground">
              {reportCategories.length > 0
                ? `${((overviewCategoryIndex % reportCategories.length) + reportCategories.length) % reportCategories.length + 1}/${reportCategories.length}`
                : "0/0"}
            </span>
            <button
              type="button"
              onClick={() =>
                onChangeCategoryIndex((prev) => (prev + 1) % reportCategories.length)
              }
              className="rounded border border-border bg-card px-1.5 py-0.5 text-muted-foreground hover:bg-secondary/70 hover:text-foreground disabled:opacity-40"
              aria-label="Próximas categorias"
              disabled={reportCategories.length <= 1}
            >
              <ChevronRight className="h-3 w-3" />
            </button>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 h-full items-stretch">
            {[0, 1].map((offset) => {
              if (reportCategories.length === 0) return null;
              const base =
                ((overviewCategoryIndex % reportCategories.length) + reportCategories.length) %
                reportCategories.length;
              const idx = (base + offset) % reportCategories.length;
              const cat = reportCategories[idx];
              const [titlePart, ...rest] = cat.label.split(":");
              const title = titlePart?.trim() || "Categoria de risco";
              const description = rest.join(":").trim();
              return (
                <motion.div
                  key={cat.id}
                  layout
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.32, ease: "easeOut" }}
                  className="rounded-lg border border-border bg-card/70 px-3 py-2 flex flex-col gap-0.5 h-full"
                >
                  <span className="text-xs font-semibold text-foreground">{title}</span>
                  {description && (
                    <span className="text-[11px] text-muted-foreground">{description}</span>
                  )}
                </motion.div>
              );
            })}
          </div>
          {reportResumoLines && (
            <div className="mt-2">
              <div className="rounded-lg border border-border bg-card/70 px-3 py-2 flex flex-col gap-0.5 h-full">
                <span className="text-[10px] uppercase tracking-wide text-muted-foreground/80">
                  Resumo de comportamento
                </span>
                {reportResumoLines.map((line, idx) => (
                  <span key={idx} className="text-[11px] text-muted-foreground">
                    {line}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default ResultsOverview;
