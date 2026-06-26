// --- Módulo: IndexHeader.tsx ---
// Cabeçalho da página Index.

import { Terminal } from "lucide-react";
import { useI18n } from "@/i18n";

// --- Componente ---
const IndexHeader = () => {
  const { t } = useI18n();
  return (
    <header className="border-b border-border bg-card/80 backdrop-blur-sm">
      <div className="container flex items-center gap-3 py-4">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 glow-primary">
          <Terminal className="h-5 w-5 text-primary" />
        </div>
        <div>
          <h1 className="font-mono text-lg font-bold text-foreground tracking-tight">{t("appTitle")}</h1>
          <p className="text-[11px] text-muted-foreground">{t("appSubtitle")}</p>
        </div>
      </div>
    </header>
  );
};

export default IndexHeader;
