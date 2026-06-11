#!/usr/bin/env python3
"""
RAT Analyzer - Interface gráfica
Permite arrastar um ficheiro .cs (compilar e analisar) ou um .exe/.dll diretamente.
"""

import json
import os
import subprocess
import sys
import threading
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext

import config

# Raiz do projeto
SCRIPT_DIR = config.PROJECT_ROOT
os.chdir(SCRIPT_DIR)


def _open_file(path: str) -> None:
    """Abre o ficheiro com a aplicação padrão do sistema."""
    path = str(Path(path).resolve())
    if sys.platform == "win32":
        os.startfile(path)
    else:
        import subprocess
        subprocess.run(["xdg-open", path], check=False, timeout=5)


def _open_folder(path: str) -> None:
    """Abre a pasta no explorador de ficheiros."""
    path = str(Path(path).resolve())
    if sys.platform == "win32":
        os.startfile(path)
    else:
        import subprocess
        subprocess.run(["xdg-open", path], check=False, timeout=5)


def find_csproj_from_cs(cs_path: Path) -> Path | None:
    """A partir de um ficheiro .cs, encontra o .csproj (mesma pasta ou pais)."""
    folder = cs_path.resolve().parent
    for _ in range(10):
        for f in folder.iterdir():
            if f.suffix.lower() == ".csproj":
                return f
        parent = folder.parent
        if parent == folder:
            break
        folder = parent
    return None


def get_publish_output(project_dir: Path) -> Path | None:
    """Devolve o diretório publish (bin/Release/<tfm>/win-x64/publish ou similar)."""
    bin_release = project_dir / "bin" / "Release"
    if not bin_release.exists():
        return None
    for tfm_dir in bin_release.iterdir():
        if tfm_dir.is_dir() and tfm_dir.name.startswith("net"):
            # Com runtime identifier (win-x64, etc.)
            for rid_dir in tfm_dir.iterdir():
                if rid_dir.is_dir():
                    pub = rid_dir / "publish"
                    if pub.exists():
                        return pub
            # Sem RID
            pub = tfm_dir / "publish"
            if pub.exists():
                return pub
    return None


def build_project(project_path: Path, log_callback=None) -> tuple[bool, str, Path | None]:
    """
    Executa dotnet publish. Devolve (sucesso, mensagem, pasta_publish).
    """
    def log(msg: str):
        if log_callback:
            log_callback(msg)

    project_dir = project_path.parent
    log(f"A compilar: {project_path.name}")
    try:
        r = subprocess.run(
            ["dotnet", "publish", str(project_path), "-c", "Release", "-r", "win-x64", "--nologo"],
            cwd=str(project_dir),
            capture_output=True,
            text=True,
            timeout=120,
        )
        if r.returncode != 0:
            err = r.stderr or r.stdout or "Erro desconhecido"
            log(f"Erro de compilação:\n{err}")
            return False, err, None

        log("Compilação concluída.")
        publish_dir = get_publish_output(project_dir)
        if not publish_dir:
            return False, "Pasta de publicação não encontrada (bin/Release/.../publish).", None
        return True, "Compilação concluída.", publish_dir
    except subprocess.TimeoutExpired:
        return False, "Compilação expirou (timeout).", None
    except FileNotFoundError:
        return False, "Comando 'dotnet' não encontrado. Instale o .NET SDK.", None
    except Exception as e:
        return False, str(e), None


def get_exe_and_dll(publish_dir: Path, project_name: str | None = None) -> tuple[Path | None, Path | None]:
    """Encontra o .exe e .dll principais na pasta publish (mesmo nome do projeto)."""
    exe_path = None
    dll_path = None
    for f in publish_dir.iterdir():
        if f.suffix.lower() == ".exe" and not f.name.startswith("host"):
            if project_name and f.stem == project_name:
                exe_path = f
                break
            if exe_path is None:
                exe_path = f
    for f in publish_dir.iterdir():
        if f.suffix.lower() != ".dll":
            continue
        if any(x in f.name.lower() for x in ("host", "runtime", "Microsoft.", "System.")):
            continue
        if project_name and f.stem == project_name:
            dll_path = f
            break
        if dll_path is None:
            dll_path = f
    return exe_path, dll_path


def run_rat_analyzer(target_path: Path, use_dotnet: bool, log_callback=None) -> tuple[bool, str]:
    """Executa rat_analyzer.py sobre target_path. Logs em tempo real via log_callback."""
    def log(msg: str):
        if log_callback:
            log_callback(msg)

    script = SCRIPT_DIR / "rat_analyzer.py"
    if not script.exists():
        return False, "rat_analyzer.py não encontrado."

    reports = str(config.REPORTS_DIR)
    cmd = [sys.executable, "-u", str(script), str(target_path), "--dotnet", "-o", reports]
    if not use_dotnet:
        cmd = [sys.executable, "-u", str(script), str(target_path), "-o", reports]

    log(f"[Início] A analisar: {target_path.name}")
    log("(Os passos abaixo aparecem à medida que avançam; a descompilação e o Ghidra podem demorar vários minutos.)")
    full_output = []
    proc = None
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(SCRIPT_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for line in iter(proc.stdout.readline, ""):
            line = line.rstrip()
            if line:
                full_output.append(line)
                log(line)
        proc.wait(timeout=300)
        out = "\n".join(full_output)
        if proc.returncode != 0:
            log(f"[Erro] Código de saída: {proc.returncode}")
            return False, out
        log(f"[Fim] Análise concluída. Consulte a pasta '{config.REPORTS_DIR.name}'.")
        return True, out
    except subprocess.TimeoutExpired:
        if proc is not None:
            try:
                proc.kill()
            except Exception:
                pass
        log("[Erro] Análise expirou (timeout 5 min).")
        return False, "Análise expirou (timeout)."
    except Exception as e:
        log(f"[Erro] {e}")
        return False, str(e)


class RATAnalyzerApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("RAT Analyzer - .cs / .exe / .dll")
        self.root.minsize(500, 520)
        self.root.geometry("580x600")

        self.cs_path: Path | None = None
        self.csproj_path: Path | None = None
        self.publish_dir: Path | None = None
        self.exe_path: Path | None = None
        self.dll_path: Path | None = None
        self.direct_file_path: Path | None = None  # .exe ou .dll carregado diretamente
        self.analyze_target = tk.StringVar(value="dll")  # "exe" ou "dll"

        self._build_ui()
        self._setup_drag_drop()

    def _build_ui(self):
        main = ttk.Frame(self.root, padding=12)
        main.pack(fill=tk.BOTH, expand=True)

        drop_frame = ttk.LabelFrame(main, text="Ficheiro a analisar", padding=8)
        drop_frame.pack(fill=tk.X, pady=(0, 8))

        self.drop_label = ttk.Label(
            drop_frame,
            text="Arraste um .cs, .exe ou .dll aqui\nou clique para escolher",
            justify=tk.CENTER,
        )
        self.drop_label.pack(pady=12, padx=20, fill=tk.X)
        self.drop_label.bind("<Button-1>", self._on_browse)

        ttk.Button(drop_frame, text="Procurar ficheiro (.cs, .exe ou .dll)...", command=self._on_browse).pack(pady=(0, 4))

        build_frame = ttk.LabelFrame(main, text="Compilar projeto", padding=8)
        build_frame.pack(fill=tk.X, pady=(0, 8))

        self.proj_label = ttk.Label(build_frame, text="Nenhum projeto selecionado.", foreground="gray")
        self.proj_label.pack(anchor=tk.W)

        self.build_btn = ttk.Button(build_frame, text="Compilar (dotnet publish)", command=self._on_build)
        self.build_btn.pack(pady=6)

        # Resultado: ficheiro direto ou saída da compilação
        out_frame = ttk.LabelFrame(main, text="Ficheiro a analisar", padding=8)
        out_frame.pack(fill=tk.X, pady=(0, 8))

        self.file_to_analyze_var = tk.StringVar(value="Nenhum ficheiro selecionado.")
        ttk.Label(out_frame, textvariable=self.file_to_analyze_var, wraplength=500).pack(anchor=tk.W)
        self.exe_var = tk.StringVar(value="")
        self.dll_var = tk.StringVar(value="")
        self._exe_label = ttk.Label(out_frame, textvariable=self.exe_var)
        self._dll_label = ttk.Label(out_frame, textvariable=self.dll_var)

        # Escolher o que analisar (só visível quando há compilação)
        choice_frame = ttk.LabelFrame(main, text="Analisar", padding=8)
        choice_frame.pack(fill=tk.X, pady=(0, 8))

        self.choice_inner = ttk.Frame(choice_frame)
        self.choice_inner.pack(fill=tk.X)
        ttk.Radiobutton(
            self.choice_inner, text="Analisar o .exe (análise estática + YARA; descompilação pode falhar)",
            variable=self.analyze_target, value="exe",
        ).pack(anchor=tk.W)
        ttk.Radiobutton(
            self.choice_inner, text="Analisar o .dll (recomendado para descompilação C#)",
            variable=self.analyze_target, value="dll",
        ).pack(anchor=tk.W)

        self.analyze_btn = ttk.Button(choice_frame, text="Executar análise RAT", command=self._on_analyze)
        self.analyze_btn.pack(pady=8)

        log_frame = ttk.LabelFrame(main, text="Log", padding=4)
        log_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        self.log_text = scrolledtext.ScrolledText(log_frame, height=10, wrap=tk.WORD, state=tk.DISABLED)
        self.log_text.pack(fill=tk.BOTH, expand=True)

    def _setup_drag_drop(self):
        try:
            import windnd
            windnd.hook_dropfiles(self.root, func=self._on_drop)
        except ImportError:
            # Sem windnd (dependência opcional da GUI): apenas botão "Procurar".
            # Para ativar drag-and-drop: pip install -r requirements-gui.txt
            self.drop_label.config(
                text=(
                    "Drag-and-drop indisponível (módulo 'windnd' em falta — "
                    "instale com: pip install -r requirements-gui.txt).\n"
                    "Clique em 'Procurar ficheiro' para selecionar .cs, .exe ou .dll"
                )
            )

    def _on_drop(self, files: list[str]):
        if not files:
            return
        path = Path(files[0].strip().strip('"'))
        if path.is_dir():
            for f in path.iterdir():
                if f.suffix.lower() == ".csproj":
                    self._set_project(f)
                    return
            self.log("Pasta sem .csproj. Arraste um ficheiro .cs.")
            return
        suf = path.suffix.lower()
        if suf == ".exe" or suf == ".dll":
            self._set_direct_file(path)
        elif suf == ".cs":
            self._set_cs_file(path)
        else:
            self.log("Arraste um ficheiro .cs, .exe ou .dll (ou pasta do projeto).")

    def _set_direct_file(self, file_path: Path):
        """Define um .exe ou .dll para analisar diretamente (sem compilar)."""
        self.direct_file_path = file_path.resolve()
        self.drop_label.config(text=f"Ficheiro: {file_path.name}\n(.exe/.dll — análise direta)")
        self.file_to_analyze_var.set(str(self.direct_file_path))
        self.exe_var.set("")
        self.dll_var.set("")
        self._exe_label.pack_forget()
        self._dll_label.pack_forget()
        self.choice_inner.pack_forget()
        self.proj_label.config(text="Ficheiro .exe/.dll carregado. Pode analisar já.", foreground="gray")
        self.log(f"Ficheiro para análise direta: {self.direct_file_path}")

    def _set_cs_file(self, cs_path: Path):
        self.direct_file_path = None
        self.cs_path = cs_path
        self.csproj_path = find_csproj_from_cs(cs_path)
        self.publish_dir = None
        self.exe_path = None
        self.dll_path = None
        self._update_file_to_analyze_display()
        self.exe_var.set("—")
        self.dll_var.set("—")
        self._exe_label.pack(anchor=tk.W)
        self._dll_label.pack(anchor=tk.W)
        self.choice_inner.pack(fill=tk.X)

        if self.csproj_path:
            self.proj_label.config(text=f"Projeto: {self.csproj_path}", foreground="black")
            self.drop_label.config(text=f"Ficheiro: {cs_path.name}\nProjeto: {self.csproj_path.name}")
            self.log(f"Ficheiro: {cs_path}\nProjeto: {self.csproj_path}")
        else:
            self.proj_label.config(text="Nenhum .csproj encontrado para este ficheiro.", foreground="red")
            self.drop_label.config(text=f"{cs_path.name}\n(.csproj não encontrado)")
            self.log("Nenhum .csproj encontrado. Coloque o .cs numa pasta com um .csproj.")

    def _set_project(self, csproj_path: Path):
        self.direct_file_path = None
        self.csproj_path = csproj_path
        self.cs_path = None
        self.publish_dir = None
        self.exe_path = None
        self.dll_path = None
        self._update_file_to_analyze_display()
        self.exe_var.set("—")
        self.dll_var.set("—")
        self._exe_label.pack(anchor=tk.W)
        self._dll_label.pack(anchor=tk.W)
        self.choice_inner.pack(fill=tk.X)
        self.proj_label.config(text=f"Projeto: {csproj_path}", foreground="black")
        self.drop_label.config(text=f"Projeto: {csproj_path.name}")
        self.log(f"Projeto: {csproj_path}")

    def _update_file_to_analyze_display(self):
        if self.direct_file_path:
            self.file_to_analyze_var.set(str(self.direct_file_path))
        elif self.exe_path or self.dll_path:
            self.file_to_analyze_var.set("Escolha .exe ou .dll acima e clique em 'Executar análise RAT'.")
        else:
            self.file_to_analyze_var.set("Nenhum ficheiro selecionado. Arraste um .cs, .exe ou .dll.")

    def _on_browse(self, *_):
        path = filedialog.askopenfilename(
            title="Selecionar ficheiro (.cs, .exe ou .dll)",
            filetypes=[
                ("Executáveis e DLLs", "*.exe;*.dll"),
                ("C#", "*.cs"),
                ("Todos", "*.*"),
            ],
            initialdir=SCRIPT_DIR,
        )
        if path:
            p = Path(path)
            if p.suffix.lower() in (".exe", ".dll"):
                self._set_direct_file(p)
            else:
                self._set_cs_file(p)
            return
        dir_path = filedialog.askdirectory(title="Ou selecionar pasta do projeto", initialdir=SCRIPT_DIR)
        if dir_path:
            d = Path(dir_path)
            for f in d.iterdir():
                if f.suffix.lower() == ".csproj":
                    self._set_project(f)
                    return
            self.log("Pasta sem .csproj.")
            messagebox.showinfo("Projeto", "Nenhum .csproj encontrado nesta pasta.")

    def _on_build(self):
        if not self.csproj_path or not self.csproj_path.exists():
            messagebox.showwarning("Compilar", "Selecione primeiro um ficheiro .cs ou projeto.")
            return

        self.build_btn.config(state=tk.DISABLED)
        self.log("\n--- Compilação ---")

        def do_build():
            def log(msg):
                self.root.after(0, lambda: self.log(msg))

            ok, msg, pub_dir = build_project(self.csproj_path, log_callback=log)
            self.root.after(0, lambda: self._after_build(ok, msg, pub_dir))

        threading.Thread(target=do_build, daemon=True).start()

    def _after_build(self, success: bool, message: str, publish_dir: Path | None):
        self.build_btn.config(state=tk.NORMAL)
        if not success:
            messagebox.showerror("Compilação", message)
            return
        self.publish_dir = publish_dir
        proj_name = self.csproj_path.stem if self.csproj_path else None
        self.exe_path, self.dll_path = get_exe_and_dll(publish_dir, proj_name) if publish_dir else (None, None)
        self.exe_var.set(str(self.exe_path) if self.exe_path else "—")
        self.dll_var.set(str(self.dll_path) if self.dll_path else "—")
        self._update_file_to_analyze_display()
        messagebox.showinfo("Compilação", "Compilação concluída. Pode escolher analisar o .exe ou .dll.")

    def _on_analyze(self):
        # Ficheiro direto (.exe/.dll) ou resultado da compilação
        if self.direct_file_path and self.direct_file_path.exists():
            path = self.direct_file_path
        else:
            target = self.analyze_target.get()
            path = self.exe_path if target == "exe" else self.dll_path
        if not path or not path.exists():
            messagebox.showwarning(
                "Análise",
                "Selecione um ficheiro .exe ou .dll (arrastar ou Procurar)\nou compile primeiro o projeto.",
            )
            return

        self.analyze_btn.config(state=tk.DISABLED)
        self.log("\n--- Análise RAT ---")

        def do_analyze():
            def log(msg):
                self.root.after(0, lambda: self.log(msg))

            ok, msg = run_rat_analyzer(path, use_dotnet=True, log_callback=log)
            self.root.after(0, lambda: self._after_analyze(ok, msg))

        threading.Thread(target=do_analyze, daemon=True).start()

    def _after_analyze(self, success: bool, message: str):
        self.analyze_btn.config(state=tk.NORMAL)
        if success:
            self._offer_view_code_and_report()
        else:
            messagebox.showerror("Análise", message[:500] + ("..." if len(message) > 500 else ""))

    def _offer_view_code_and_report(self):
        """Lê last_analysis.json e oferece abrir relatório e ver código descompilado/desobfuscado."""
        last_path = config.REPORTS_DIR / "last_analysis.json"
        if not last_path.exists():
            messagebox.showinfo("Análise", f"Análise concluída. Consulte a pasta '{config.REPORTS_DIR.name}'.")
            return
        try:
            with open(last_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            messagebox.showinfo("Análise", f"Análise concluída. Consulte a pasta '{config.REPORTS_DIR.name}'.")
            return
        consolidated = data.get("consolidated_file", "")
        deobfuscated = data.get("deobfuscated_file", "")
        disassembly = data.get("disassembly_file", "")
        decompiled_c = data.get("decompiled_c_file", "")
        report_path = data.get("report_path", "")
        decompiled_dir = data.get("decompiled_dir", "")
        decompilation_error_summary = data.get("decompilation_error_summary", "")
        flagged_indicators = data.get("flagged_indicators", [])

        win = tk.Toplevel(self.root)
        win.title("Resultado da análise")
        win.geometry("480x340")
        win.transient(self.root)
        frm = ttk.Frame(win, padding=16)
        frm.pack(fill=tk.BOTH, expand=True)
        ttk.Label(frm, text="Análise concluída.", font=("", 10, "bold")).pack(anchor=tk.W, pady=(0, 8))
        has_code = False
        if consolidated and Path(consolidated).exists():
            ttk.Label(frm, text="Pode ver o código resultante:", font=("", 9)).pack(anchor=tk.W)
            ttk.Button(frm, text="Ver código descompilado (.cs)", command=lambda: self._show_code_window(Path(consolidated), "Código descompilado")).pack(anchor=tk.W, pady=2)
            has_code = True
        if deobfuscated and Path(deobfuscated).exists():
            ttk.Button(frm, text="Ver código desobfuscado (.cs)", command=lambda: self._show_code_window(Path(deobfuscated), "Código desobfuscado")).pack(anchor=tk.W, pady=2)
            has_code = True
        if disassembly and Path(disassembly).exists():
            if not has_code:
                ttk.Label(frm, text="Binário nativo/AOT — desmontagem em assembly:", font=("", 9)).pack(anchor=tk.W)
            ttk.Button(frm, text="Ver assembly (desmontagem .asm)", command=lambda: self._show_code_window(Path(disassembly), "Assembly")).pack(anchor=tk.W, pady=2)
            has_code = True
        if decompiled_c and Path(decompiled_c).exists():
            ttk.Button(
                frm,
                text="Ver código decompilado (pseudo-C) com highlights",
                command=lambda: self._show_code_window(Path(decompiled_c), "Pseudo-C (Ghidra)", highlights=flagged_indicators),
            ).pack(anchor=tk.W, pady=2)
            has_code = True
        if decompiled_dir and Path(decompiled_dir).is_dir():
            ttk.Button(frm, text="Abrir pasta do código/assembly", command=lambda: _open_folder(decompiled_dir)).pack(anchor=tk.W, pady=2)
        if not has_code:
            if decompilation_error_summary:
                lbl = ttk.Label(frm, text=decompilation_error_summary, foreground="#c00", wraplength=440, justify=tk.LEFT)
                lbl.pack(anchor=tk.W, pady=(4, 8))
            else:
                ttk.Label(frm, text="(Nenhum código .NET descompilado — ficheiro pode não ser .NET ou ILSpy não instalado)", foreground="gray", wraplength=440).pack(anchor=tk.W, pady=(4, 8))
        if report_path and Path(report_path).exists():
            ttk.Button(frm, text="Abrir relatório (.txt)", command=lambda: _open_file(report_path)).pack(anchor=tk.W, pady=4)
        ttk.Button(frm, text="Fechar", command=win.destroy).pack(anchor=tk.W, pady=(12, 0))

    def _show_code_window(self, file_path: Path, title: str, highlights: list | None = None):
        """Abre uma janela com o conteúdo do ficheiro (só leitura). Se highlights for fornecido, realça as ocorrências."""
        if not file_path.exists():
            messagebox.showwarning("Ficheiro", f"Ficheiro não encontrado: {file_path}")
            return
        win = tk.Toplevel(self.root)
        win.title(f"{title} — {file_path.name}")
        win.geometry("900x600")
        win.transient(self.root)
        frm = ttk.Frame(win, padding=8)
        frm.pack(fill=tk.BOTH, expand=True)
        ttk.Button(frm, text="Abrir pasta", command=lambda: _open_folder(str(file_path.parent))).pack(anchor=tk.W)
        nav_state = {"ranges": [], "idx": 0}
        if highlights and len(highlights) > 0:
            ttk.Label(
                frm,
                text="Amarelo = indicadores que deram flag (YARA, análise estática, evasão)",
                foreground="#666",
                font=("", 8),
            ).pack(anchor=tk.W)
            nav = ttk.Frame(frm)
            nav.pack(anchor=tk.W, pady=(2, 0))

            def _ensure_ranges():
                if not nav_state["ranges"]:
                    nav_state["ranges"] = list(txt.tag_ranges("rat_flag"))
                    nav_state["idx"] = 0

            def _goto_next():
                _ensure_ranges()
                r = nav_state["ranges"]
                if not r:
                    return
                start = r[nav_state["idx"]]
                txt.see(start)
                nav_state["idx"] = (nav_state["idx"] + 2) % len(r)

            def _goto_prev():
                _ensure_ranges()
                r = nav_state["ranges"]
                if not r:
                    return
                nav_state["idx"] = (nav_state["idx"] - 2) % len(r)
                start = r[nav_state["idx"]]
                txt.see(start)

            ttk.Button(nav, text="◀ Anterior", command=_goto_prev).pack(side=tk.LEFT, padx=(0, 4))
            ttk.Button(nav, text="Seguinte ▶", command=_goto_next).pack(side=tk.LEFT)

        txt = scrolledtext.ScrolledText(frm, wrap=tk.WORD, font=("Consolas", 10), state=tk.NORMAL)
        txt.pack(fill=tk.BOTH, expand=True, pady=(8, 0))
        try:
            content = file_path.read_text(encoding="utf-8", errors="replace")
            txt.insert(tk.END, content)
        except Exception as e:
            txt.insert(tk.END, f"Erro ao ler ficheiro: {e}")
        # Aplicar highlights (indicadores que deram flag no RAT Analyzer)
        if highlights and isinstance(highlights, list) and len(highlights) > 0:
            txt.tag_config("rat_flag", background="#ffeb3b", foreground="#000")
            for indicator in highlights:
                if not indicator or not isinstance(indicator, str) or len(indicator) < 3:
                    continue
                start_idx = "1.0"
                while True:
                    pos = txt.search(indicator, start_idx, tk.END, nocase=False)
                    if not pos:
                        break
                    end_idx = f"{pos}+{len(indicator)}c"
                    txt.tag_add("rat_flag", pos, end_idx)
                    start_idx = end_idx
        txt.config(state=tk.DISABLED)

    def log(self, msg: str):
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, msg.strip() + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    app = RATAnalyzerApp()
    app.run()
