// --- Módulo: StubDriverConfirmDialog.tsx ---
// Confirmação antes de submeter análise dinâmica com driver stub.

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useI18n } from "@/i18n";

type StubDriverConfirmDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onContinue: () => void;
  onStaticOnly: () => void;
};

const StubDriverConfirmDialog = ({
  open,
  onOpenChange,
  onContinue,
  onStaticOnly,
}: StubDriverConfirmDialogProps) => {
  const { t } = useI18n();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("stubConfirmTitle")}</DialogTitle>
          <DialogDescription>{t("stubConfirmBody")}</DialogDescription>
        </DialogHeader>
        <DialogFooter className="gap-2 sm:gap-0">
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            className="rounded-lg border border-border bg-secondary px-4 py-2 font-mono text-xs text-secondary-foreground hover:bg-secondary/80"
          >
            {t("stubConfirmCancel")}
          </button>
          <button
            type="button"
            onClick={onStaticOnly}
            className="rounded-lg border border-border bg-card px-4 py-2 font-mono text-xs text-foreground hover:bg-secondary/60"
          >
            {t("stubConfirmStaticOnly")}
          </button>
          <button
            type="button"
            onClick={onContinue}
            className="rounded-lg bg-amber-600 px-4 py-2 font-mono text-xs font-semibold text-white hover:bg-amber-500"
          >
            {t("stubConfirmContinue")}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

export default StubDriverConfirmDialog;
