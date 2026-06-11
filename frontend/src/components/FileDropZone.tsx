import React, { useCallback, useState } from "react";
import { motion } from "framer-motion";
import { Upload, FileCode, X } from "lucide-react";
import { toast } from "@/components/ui/sonner";

interface FileDropZoneProps {
  onFileLoaded: (file: File) => void;
  currentFile: File | null;
  onClear: () => void;
}

const ACCEPTED_EXTENSIONS = [".cs", ".dll", ".exe"];
/** Alinhado com o limite do backend (RATANALYZER_MAX_UPLOAD_MB, default 100 MB). */
export const MAX_FILE_SIZE_BYTES = 100 * 1024 * 1024;

const FileDropZone: React.FC<FileDropZoneProps> = ({ onFileLoaded, currentFile, onClear }) => {
  const [isDragging, setIsDragging] = useState(false);

  const handleFile = useCallback(
    (file: File) => {
      const dotIdx = file.name.lastIndexOf(".");
      const ext = dotIdx >= 0 ? file.name.substring(dotIdx).toLowerCase() : "";
      if (!ACCEPTED_EXTENSIONS.includes(ext)) {
        toast.error("Tipo de ficheiro não suportado", {
          description: `"${file.name}" foi rejeitado. Apenas ficheiros ${ACCEPTED_EXTENSIONS.join(", ")} são aceites.`,
        });
        return;
      }
      if (file.size > MAX_FILE_SIZE_BYTES) {
        toast.error("Ficheiro demasiado grande", {
          description: `"${file.name}" tem ${(file.size / (1024 * 1024)).toFixed(1)} MB. O limite é 100 MB.`,
        });
        return;
      }
      onFileLoaded(file);
    },
    [onFileLoaded]
  );

  const onDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }, [handleFile]);

  const onDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const onDragLeave = useCallback(() => setIsDragging(false), []);

  const onInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFile(file);
    // Permite voltar a selecionar o mesmo ficheiro depois de limpar.
    e.target.value = "";
  }, [handleFile]);

  if (currentFile) {
    return (
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="relative flex items-center gap-4 rounded-lg border border-primary/30 bg-primary/5 px-6 py-4"
      >
        <FileCode className="h-8 w-8 text-primary" />
        <div className="flex-1">
          <p className="font-mono text-sm font-semibold text-foreground">{currentFile.name}</p>
          <p className="text-xs text-muted-foreground">
            {(currentFile.size / 1024).toFixed(1)} KB
          </p>
        </div>
        <button
          type="button"
          onClick={onClear}
          aria-label="Remover ficheiro selecionado"
          className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
        >
          <X className="h-4 w-4" />
        </button>
      </motion.div>
    );
  }

  return (
    <motion.div
      onDrop={onDrop}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      animate={{
        borderColor: isDragging ? "hsl(160, 80%, 45%)" : "hsl(220, 14%, 18%)",
        backgroundColor: isDragging ? "hsla(160, 80%, 45%, 0.05)" : "transparent",
      }}
      transition={{ duration: 0.2 }}
      className="relative flex cursor-pointer flex-col items-center justify-center gap-4 rounded-xl border-2 border-dashed py-16 transition-colors"
    >
      <input
        type="file"
        accept=".cs,.dll,.exe"
        onChange={onInputChange}
        aria-label="Selecionar ficheiro para análise"
        className="absolute inset-0 cursor-pointer opacity-0"
      />
      <motion.div
        animate={{ y: isDragging ? -4 : 0 }}
        transition={{ type: "spring", stiffness: 300 }}
      >
        <Upload className="h-10 w-10 text-muted-foreground" />
      </motion.div>
      <div className="text-center">
        <p className="text-sm font-medium text-foreground">
          Arraste o ficheiro para aqui
        </p>
        <p className="mt-1 text-xs text-muted-foreground">
          ou clique para selecionar — .cs, .dll, .exe (máx. 100 MB)
        </p>
      </div>
    </motion.div>
  );
};

export default FileDropZone;
