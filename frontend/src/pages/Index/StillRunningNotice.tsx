// --- Módulo: StillRunningNotice.tsx ---
// Aviso quando o job ainda está em execução no backend.

import React from "react";
import { Hourglass } from "lucide-react";
import { useI18n } from "@/i18n";

type StillRunningNoticeProps = {
  jobId: string;
  lastStatus: string;
};

// --- Componente ---
const StillRunningNotice: React.FC<StillRunningNoticeProps> = ({ jobId, lastStatus }) => {
  const { t } = useI18n();
  return (
    <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2.5 text-[12px] font-mono text-foreground space-y-2">
      <div className="flex items-center gap-2">
        <Hourglass className="h-4 w-4 shrink-0 text-amber-500" />
        <span>{t("stillRunning", { status: lastStatus })}</span>
      </div>
      <p className="text-[11px] text-muted-foreground">
        {t("stillRunningHint", { jobId })}
      </p>
    </div>
  );
};

export default StillRunningNotice;
