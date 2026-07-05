// --- Módulo: StubDriverBanner.tsx ---
// Aviso visível quando a análise dinâmica está em modo stub (sem execução real).

import { AlertTriangle } from "lucide-react";
import { useI18n } from "@/i18n";

type StubDriverBannerProps = {
  variant: "configured" | "result";
};

const StubDriverBanner = ({ variant }: StubDriverBannerProps) => {
  const { t } = useI18n();

  return (
    <div
      role="alert"
      className="rounded-lg border border-amber-500/50 bg-amber-500/10 px-4 py-3 text-amber-950 dark:text-amber-100"
    >
      <div className="flex items-start gap-3">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600 dark:text-amber-400" />
        <div className="space-y-1 font-mono text-[11px] leading-relaxed">
          <p className="text-xs font-semibold text-amber-900 dark:text-amber-50">
            {t("stubBannerTitle")}
          </p>
          <p className="text-amber-900/90 dark:text-amber-100/90">
            {variant === "configured" ? t("stubBannerConfigured") : t("stubBannerResult")}
          </p>
        </div>
      </div>
    </div>
  );
};

export default StubDriverBanner;
