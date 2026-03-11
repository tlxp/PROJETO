import React, { useCallback, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Upload, FileCode, X } from "lucide-react";

interface FileDropZoneProps {
  onFileLoaded: (file: File, content: string) => void;
  currentFile: File | null;
  onClear: () => void;
}

const ACCEPTED_EXTENSIONS = [".cs", ".dll", ".exe"];

const FileDropZone: React.FC<FileDropZoneProps> = ({ onFileLoaded, currentFile, onClear }) => {
  const [isDragging, setIsDragging] = useState(false);

  const handleFile = useCallback((file: File) => {
    const ext = file.name.substring(file.name.lastIndexOf(".")).toLowerCase();
    if (!ACCEPTED_EXTENSIONS.includes(ext)) {
      return;
    }
    const reader = new FileReader();
    reader.onload = (e) => {
      onFileLoaded(file, e.target?.result as string || "[Binary file]");
    };
    if (ext === ".cs") {
      reader.readAsText(file);
    } else {
      onFileLoaded(file, "[Binary file — " + file.name + "]");
    }
  }, [onFileLoaded]);

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
          onClick={onClear}
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
          ou clique para selecionar — .cs, .dll, .exe
        </p>
      </div>
    </motion.div>
  );
};

export default FileDropZone;
