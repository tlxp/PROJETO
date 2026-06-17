import { describe, it, expect, vi, beforeEach } from "vitest";
import { screen, fireEvent } from "@testing-library/react";
import FileDropZone from "@/components/FileDropZone";
import { renderWithI18n } from "@/test/renderWithI18n";

vi.mock("@/components/ui/sonner", () => ({
  toast: {
    error: vi.fn(),
    success: vi.fn(),
  },
}));

import { toast } from "@/components/ui/sonner";

describe("FileDropZone", () => {
  const onFileLoaded = vi.fn();
  const onClear = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renderiza zona de arrastar quando não há ficheiro", () => {
    renderWithI18n(<FileDropZone onFileLoaded={onFileLoaded} currentFile={null} onClear={onClear} />);
    expect(screen.getByText(/arrast/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/selecionar ficheiro/i)).toBeInTheDocument();
  });

  it("mostra ficheiro selecionado e botão de remover", () => {
    const file = new File(["MZ"], "test.exe", { type: "application/octet-stream" });
    renderWithI18n(<FileDropZone onFileLoaded={onFileLoaded} currentFile={file} onClear={onClear} />);
    expect(screen.getByText("test.exe")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /remover ficheiro/i }));
    expect(onClear).toHaveBeenCalledOnce();
  });

  it("rejeita extensão não suportada", () => {
    renderWithI18n(<FileDropZone onFileLoaded={onFileLoaded} currentFile={null} onClear={onClear} />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const bad = new File(["x"], "notes.txt", { type: "text/plain" });
    fireEvent.change(input, { target: { files: [bad] } });
    expect(onFileLoaded).not.toHaveBeenCalled();
    expect(toast.error).toHaveBeenCalled();
  });

  it("aceita ficheiro .exe válido", () => {
    renderWithI18n(<FileDropZone onFileLoaded={onFileLoaded} currentFile={null} onClear={onClear} />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const good = new File(["MZ"], "mal.exe", { type: "application/octet-stream" });
    fireEvent.change(input, { target: { files: [good] } });
    expect(onFileLoaded).toHaveBeenCalledWith(good);
  });
});
