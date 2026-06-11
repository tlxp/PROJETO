import React from "react";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { AnalysisResult, ReportCategory } from "@/lib/analysis";

type ResultsOverviewProps = {
  result: AnalysisResult;
  reportCategories: ReportCategory[];
  reportResumoLines: string[] | null;
  overviewCategoryIndex: number;
  onChangeCategoryIndex: (updater: (prev: number) => number) => void;
  hasJobId: boolean;
};

/** Overview da análise + categorias navegáveis do relatório. */
const ResultsOverview: React.FC<ResultsOverviewProps> = ({
  result,
  reportCategories,
  reportResumoLines,
  overviewCategoryIndex,
  onChangeCategoryIndex,
  hasJobId,
}) => {
  if (reportCategories.length === 0) return null;

  return (
    <div className="grid gap-3 md:grid-cols-4 items-stretch text-[11px] font-mono text-muted-foreground">
      {/* Overview fixo à esquerda */}
      <div className="md:col-span-2 rounded-lg border border-border bg-card/70 px-3 py-2">
        <div className="text-[10px] uppercase tracking-wide text-muted-foreground/80 mb-1">
          Overview da análise
        </div>
        <div className="flex flex-wrap items-center gap-2 text-foreground">
          <span className="text-xs font-semibold">
            Risco {result.riskScore}/100{" "}
            {result.riskLevel && `(${result.riskLevel.toUpperCase()})`}
          </span>
          {result.flaggedIndicators && result.flaggedIndicators.length > 0 && (
            <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] text-primary">
              {result.flaggedIndicators.length} indicadores com flag no código
            </span>
          )}
        </div>
        <div className="mt-1 text-[11px] text-muted-foreground">
          Use os marcadores do relatório e as funções suspeitas para navegar rapidamente entre as zonas mais críticas do pseudo-C e do IL.
        </div>
        {(result.obfuscatedSnippetsFile || result.obfuscatedSnippetsDeobfuscatedFile) && !hasJobId && (
          <div className="mt-1.5 rounded border border-primary/30 bg-primary/5 px-2 py-1 text-[10px] font-mono text-muted-foreground">
            Trechos obfuscados extraídos: ver caminhos na secção DEOBFUSCAÇÃO do relatório.
          </div>
        )}
        {(reportCategories.some((c) => /obfus/i.test(c.label)) || (result.obfuscationIndicatorCount ?? 0) > 0) && (
          <div className="mt-1.5 text-[10px] text-muted-foreground">
            A categoria <strong>Obfuscation</strong> do relatório reflete os indicadores ou trechos que os botões &quot;Ver trechos obfuscados&quot; / &quot;Ver trechos deobfuscados&quot; mostram.
          </div>
        )}
      </div>

      {/* Dois cartões à direita, navegáveis com setas */}
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
              ((overviewCategoryIndex % reportCategories.length) +
                reportCategories.length) %
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
                <span className="text-[10px] uppercase tracking-wide text-muted-foreground/80">
                  Categoria de risco do relatório
                </span>
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
    </div>
  );
};

export default ResultsOverview;
