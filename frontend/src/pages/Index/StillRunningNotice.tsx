import React from "react";
import { Hourglass } from "lucide-react";

type StillRunningNoticeProps = {
  jobId: string;
  lastStatus: string;
};

/**
 * Aviso mostrado quando o polling esgota o tempo máximo de espera mas o job
 * continua em execução no backend (não é tratado como erro).
 */
const StillRunningNotice: React.FC<StillRunningNoticeProps> = ({ jobId, lastStatus }) => (
  <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2.5 text-[12px] font-mono text-foreground space-y-2">
    <div className="flex items-center gap-2">
      <Hourglass className="h-4 w-4 shrink-0 text-amber-500" />
      <span>
        A análise ainda está em execução no backend (estado atual: {lastStatus}).
      </span>
    </div>
    <p className="text-[11px] text-muted-foreground">
      Volte mais tarde e recarregue esta página — o resultado fica disponível em{" "}
      <span className="text-foreground break-all">/analysis/{jobId}</span>.
    </p>
  </div>
);

export default StillRunningNotice;
