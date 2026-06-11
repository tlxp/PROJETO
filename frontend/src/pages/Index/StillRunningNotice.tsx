import React from "react";
import { Hourglass } from "lucide-react";

type StillRunningNoticeProps = {
  jobId: string;
  lastStatus: string;
  isWaiting: boolean;
  onResume: () => void;
};

/**
 * Aviso mostrado quando o polling esgota o tempo máximo de espera mas o job
 * continua em execução no backend (não é tratado como erro).
 */
const StillRunningNotice: React.FC<StillRunningNoticeProps> = ({
  jobId,
  lastStatus,
  isWaiting,
  onResume,
}) => (
  <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2.5 text-[12px] font-mono text-foreground space-y-2">
    <div className="flex items-center gap-2">
      <Hourglass className="h-4 w-4 shrink-0 text-amber-500" />
      <span>
        A análise ainda está em execução no backend (estado atual: {lastStatus}).
      </span>
    </div>
    <p className="text-[11px] text-muted-foreground">
      Pode continuar a aguardar aqui ou voltar mais tarde e recarregar esta página — o resultado
      fica disponível em <span className="text-foreground break-all">/analysis/{jobId}</span>.
    </p>
    <button
      type="button"
      onClick={onResume}
      disabled={isWaiting}
      className="rounded border border-amber-500/50 bg-amber-500/15 px-3 py-1.5 text-[11px] text-foreground transition-colors hover:bg-amber-500/25 disabled:opacity-50"
    >
      {isWaiting ? "A aguardar..." : "Continuar a aguardar"}
    </button>
  </div>
);

export default StillRunningNotice;
