"""
Decompilação de binários nativos para pseudo-C usando PyGhidra (Ghidra).
Converte o assembly/código de máquina em código C legível (decompilador Ghidra).
Requer: Ghidra instalado e variável GHIDRA_INSTALL_DIR (ou install_dir).

--- O que se passa e porquê ---

O decompilador do Ghidra analisa o fluxo de controlo (branches, jumps, switches).
Por defeito tem limites conservadores para evitar explosão de tempo/memória.

1) "Could not recover jumptable at 0x... Too many branches"
   - Em C, um switch com muitos cases é compilado para uma "jumptable": uma tabela de
     endereços e um salto indirecto (jmp [base+index]). O decompilador tenta recuperar
     essa tabela para voltar a mostrar um switch em pseudo-C.
   - O Ghidra limita o número de entradas que aceita numa jumptable (por defeito 1024).
     Se a função tiver um switch com mais casos, ou o análisis encontrar mais branches
     do que o limite, o decompilador desiste e não recupera o switch.
   - Consequência: em vez de switch/case limpo, aparece código mais confuso e o aviso
     em comentário. Aumentar DECOMPILER_MAX_JUMPTABLE_ENTRIES reduz este problema.

2) "Treating indirect jump as call"
   - Um "indirect jump" é um salto para um endereço calculado em tempo de execução
     (ex.: jmp rax, ou call [r8+offset]). Pode ser um switch (jumptable), um call
     através de função ponteiro, ou outro padrão.
   - Se o decompilador não conseguir classificar o salto como jumptable (por ex. por
     "Too many branches" ou análise incompleta), trata o indirect jump como se fosse
     uma chamada de função (call), para não perder o fluxo. Daí o aviso.
   - Com "eliminate unreachable" ativado, código que fica para lá desse "call" pode
     ser considerado inalcançável e removido. Desativar (DECOMPILER_ELIMINATE_UNREACHABLE
     = False) preserva esse código. Inferir ponteiros constantes (DECOMPILER_INFER_CONST_PTR)
     ajuda a resolver alguns indirect jumps para endereços conhecidos.

3) Melhorias possíveis (sem alterar o binário):
   - Aumentar DECOMPILER_MAX_JUMPTABLE_ENTRIES (ex.: 4M–8M) se tiver memória; reduz "Too many branches".
   - DECOMPILER_HIDE_JUMPTABLE_WARNINGS: esconder os comentários WARNING no pseudo-C (saída mais limpa).
   - Na GUI do Ghidra: scripts FindUnrecoveredSwitchesScript e SwitchOverride para recuperar switches à mão.
"""

import os
import shutil
import sys
from pathlib import Path
from typing import Callable, Dict, Optional

from artifact_naming import short_stem
import config

def _jdk_root_has_java_bin(home: Path) -> bool:
    name = "java.exe" if sys.platform == "win32" else "java"
    return home.is_dir() and (home / "bin" / name).is_file()


def _prepend_path(directory: str) -> None:
    if not directory:
        return
    norm = os.path.normpath(directory)
    sep = os.pathsep
    path = os.environ.get("PATH", "")
    parts = path.split(sep) if path else []
    if norm in parts:
        return
    os.environ["PATH"] = norm + sep + path if path else norm


def _ensure_java_home_for_ghidra() -> None:
    """
    O Ghidra chama LaunchSupport com `-jdk_home`; o processo Python (uvicorn) pode ter
    arrancado antes de JAVA_HOME existir no ambiente. Descobre JDK 21 em disco / registo
    Windows e define os.environ antes de import pyghidra / pyghidra.start().
    """
    existing = (os.environ.get("JAVA_HOME") or "").strip()
    if existing:
        p = Path(existing)
        if _jdk_root_has_java_bin(p):
            _prepend_path(str(p / "bin"))
            return

    if sys.platform == "win32":
        try:
            import winreg

            for root, subkey in (
                (winreg.HKEY_CURRENT_USER, r"Environment"),
                (
                    winreg.HKEY_LOCAL_MACHINE,
                    r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
                ),
            ):
                try:
                    with winreg.OpenKey(root, subkey) as k:
                        val, _ = winreg.QueryValueEx(k, "JAVA_HOME")
                        if val and _jdk_root_has_java_bin(Path(str(val).strip())):
                            home = str(Path(str(val).strip()).resolve())
                            os.environ["JAVA_HOME"] = home
                            _prepend_path(str(Path(home) / "bin"))
                            return
                except OSError:
                    continue
        except Exception:
            pass

        pf = os.environ.get("ProgramFiles", r"C:\Program Files")
        adoptium = Path(pf) / "Eclipse Adoptium"
        if adoptium.is_dir():
            try:
                matches = sorted(
                    adoptium.glob("jdk-21*"),
                    key=lambda x: x.name,
                    reverse=True,
                )
                for d in matches:
                    if _jdk_root_has_java_bin(d):
                        home = str(d.resolve())
                        os.environ["JAVA_HOME"] = home
                        _prepend_path(str(d / "bin"))
                        return
            except Exception:
                pass

        for vendor_glob in (
            (Path(pf) / "Microsoft", "jdk-*"),
            (Path(pf) / "Amazon Corretto", "jdk*"),
        ):
            base, pat = vendor_glob
            if not base.is_dir():
                continue
            try:
                for d in sorted(base.glob(pat), key=lambda x: x.name, reverse=True):
                    if "21" not in d.name:
                        continue
                    if _jdk_root_has_java_bin(d):
                        home = str(d.resolve())
                        os.environ["JAVA_HOME"] = home
                        _prepend_path(str(d / "bin"))
                        return
            except Exception:
                pass

    if sys.platform == "darwin":
        bases = (Path("/Library/Java/JavaVirtualMachines"),)
        for base in bases:
            if not base.is_dir():
                continue
            try:
                for home in sorted(base.glob("jdk-21*.jdk/Contents/Home"), reverse=True):
                    if _jdk_root_has_java_bin(home):
                        os.environ["JAVA_HOME"] = str(home.resolve())
                        _prepend_path(str(home / "bin"))
                        return
            except Exception:
                pass

    if sys.platform.startswith("linux"):
        try:
            jvm = Path("/usr/lib/jvm")
            if jvm.is_dir():
                for home in sorted(jvm.glob("java-21-*"), reverse=True):
                    if _jdk_root_has_java_bin(home):
                        os.environ["JAVA_HOME"] = str(home.resolve())
                        _prepend_path(str(home / "bin"))
                        return
        except Exception:
            pass


def _format_pyghidra_start_error(exc: BaseException) -> str:
    """
    Erros típicos: LaunchSupport / -jdk_home / exit status 1 → JDK em falta ou versão errada.
    Ghidra 12.x requer JDK 21 (64-bit).
    """
    msg = str(exc)
    core = f"Falha ao iniciar Ghidra (verifique GHIDRA_INSTALL_DIR): {msg}"
    low = msg.lower()
    needs_java_hint = any(
        x in low
        for x in (
            "launchsupport",
            "jdk_home",
            "-jdk",
            "java ",
            "non-zero exit status",
            "cannot find java",
            "java_home",
            "failed to locate",
            "no jdk",
        )
    ) or "LaunchSupport" in msg

    if not needs_java_hint:
        return core

    return (
        core
        + "\n\n--- Java / JDK (requisito do Ghidra 12) ---\n"
        "O Ghidra 12 precisa de um JDK 21 de 64 bits no sistema. Ter apenas .NET ou Python não chega.\n\n"
        "Passos sugeridos:\n"
        "  1. Instale JDK 21 (por exemplo Eclipse Temurin ou Amazon Corretto).\n"
        "  2. Defina a variável de utilizador JAVA_HOME para a raiz do JDK "
        '(por exemplo a pasta que contém bin\\java.exe no JDK 21).\n'
        "  3. Confirme num terminal: java -version  → deve mostrar versão 21.\n"
        "  4. Reinicie o backend Python se já estiver em execução sem JAVA_HOME; "
        "o servidor também tenta detetar JDK 21 em disco ao iniciar o Ghidra.\n\n"
        "Temurin 21: https://adoptium.net/temurin/releases/?version=21\n"
        "Corretto 21: https://docs.aws.amazon.com/corretto/latest/corretto-21-ug/downloads-list.html"
    )


# Limites para não gerar ficheiros enormes
# MAX_FUNCTIONS muito alto → na prática sem limite de número de funções
MAX_FUNCTIONS = 10**9
# None = sem limite global de tamanho; controlo de tamanho passa a ser feito no backend (API)
MAX_OUTPUT_CHARS = None
TIMEOUT_SECONDS_PER_FUNCTION = 600

# Limites do decompilador Ghidra: permitir que recupere jumptables/switches em vez de falhar
# (default no Ghidra é 1024; "Too many branches" = decompilador desistiu por limite de entradas)
# Limite de entradas na jumptable: quanto maior, menos "Too many branches" (mais RAM/tempo por função)
DECOMPILER_MAX_JUMPTABLE_ENTRIES = 4194304  # 4M (default Ghidra 1024); aumentar para 8M se ainda falhar
DECOMPILER_MAX_INSTRUCTIONS = 500000        # funções muito grandes ainda decompiladas
DECOMPILER_TIMEOUT_SECS = 300               # 5 min por função — mais tempo para análise profunda e jumptables
DECOMPILER_MAX_PAYLOAD_MB = 64              # payload máximo (MB) por função — evita abort em funções com muitos cases

# Recursão / tratamento de branches: não eliminar código "unreachable" para preservar todos os branches
# quando o decompilador não consegue recuperar um jumptable (evita perder código com "indirect jump as call")
DECOMPILER_ELIMINATE_UNREACHABLE = False
# Inferir ponteiros constantes: ajuda a resolver indirect jumps para endereços conhecidos
DECOMPILER_INFER_CONST_PTR = True
# Esconder comentários "WARNING: Could not recover jumptable" / "Treating indirect jump as call" no pseudo-C
DECOMPILER_HIDE_JUMPTABLE_WARNINGS = True


def _apply_our_options(opts):
    """
    Aplica os nossos limites e opções ao DecompileOptions.
    Cada setter é em try/except para não falhar em versões do Ghidra onde o método não exista.
    """
    def _set(method, *args):
        if hasattr(opts, method):
            getattr(opts, method)(*args)

    _set("setMaxJumpTableEntries", DECOMPILER_MAX_JUMPTABLE_ENTRIES)
    _set("setMaxInstructions", DECOMPILER_MAX_INSTRUCTIONS)
    _set("setDefaultTimeout", DECOMPILER_TIMEOUT_SECS)
    _set("setMaxPayloadMBytes", DECOMPILER_MAX_PAYLOAD_MB)
    _set("setEliminateUnreachable", DECOMPILER_ELIMINATE_UNREACHABLE)
    _set("setInferConstantPointers", DECOMPILER_INFER_CONST_PTR)
    if DECOMPILER_HIDE_JUMPTABLE_WARNINGS:
        _set("setWARNCommentIncluded", False)


def _build_decompile_options(program=None):
    """
    Constrói DecompileOptions com limites altos e opções de recursão/branches para recuperar
    jumptables (assembly -> switch) e tratar melhor indirect jumps.
    Ordem: definir as nossas opções primeiro; depois grabFromProgram (linguagem/proto do programa);
    por fim reaplicar as nossas opções para garantir que não foram sobrescritas.
    As opções devem ser aplicadas ao DecompInterface *antes* de openProgram().
    """
    try:
        from ghidra.app.decompiler import DecompileOptions
        opts = DecompileOptions()
        # 1) Aplicar os nossos limites/opções primeiro
        _apply_our_options(opts)
        # 2) Carregar opções do programa (linguagem, proto) — pode sobrescrever
        if program is not None:
            try:
                opts.grabFromProgram(program)
            except Exception:
                pass
        # 3) Reaplicar as nossas opções para garantir que ficam ativas
        _apply_our_options(opts)
        return opts
    except Exception:
        return None


def decompile_binary_to_c(
    binary_path: str,
    output_path: Optional[str] = None,
    output_root: str = "decompiled",
    ghidra_install_dir: Optional[str] = None,
    progress_callback: Optional[Callable[[float], None]] = None,
) -> Dict:
    """
    Decompila um binário (exe/dll nativo) para pseudo-C usando o decompilador Ghidra via PyGhidra.
    :param binary_path: Caminho para o .exe ou .dll
    :param output_path: Ficheiro .c de saída (opcional)
    :param output_root: Pasta base se output_path for None
    :param ghidra_install_dir: Pasta de instalação do Ghidra (ou use env GHIDRA_INSTALL_DIR)
    :return: { "success", "output_file", "error", "functions_decompiled" }
    """
    result = {"success": False, "output_file": "", "error": "", "functions_decompiled": 0}
    path = Path(binary_path).resolve()
    if not path.exists():
        result["error"] = f"Ficheiro não encontrado: {path}"
        return result

    _ensure_java_home_for_ghidra()

    try:
        import pyghidra
    except ImportError:
        result["error"] = (
            "PyGhidra não encontrado. Instale com: pip install pyghidra. "
            "Requer também Ghidra 12+ instalado e GHIDRA_INSTALL_DIR definido."
        )
        return result

    sstem = short_stem(path.stem)
    out_file = Path(output_path) if output_path else (Path(output_root).resolve() / sstem / f"{sstem}_decompiled.c")
    out_file.parent.mkdir(parents=True, exist_ok=True)

    # Forçar re-análise: apagar projeto Ghidra existente (.rep/.gpr) para que as opções
    # e a análise sejam aplicadas de raiz (evita cache com limites antigos).
    project_name = f"{sstem}_ghidra"
    project_dir = out_file.parent / f"{project_name}.rep"
    project_file = out_file.parent / f"{project_name}.gpr"
    try:
        if project_dir.exists() and project_dir.is_dir():
            shutil.rmtree(project_dir)
        if project_file.exists():
            project_file.unlink()
    except Exception:
        pass

    try:
        if not pyghidra.started():
            pyghidra.start(verbose=False, install_dir=ghidra_install_dir)
    except Exception as e:
        result["error"] = _format_pyghidra_start_error(e)
        return result

    try:
        with pyghidra.open_program(
            str(path),
            project_location=str(out_file.parent),
            project_name=f"{sstem}_ghidra",
            analyze=True,
        ) as flat_api:
            program = flat_api.getCurrentProgram()
            # Usar DecompInterface diretamente e aplicar opções ANTES de openProgram(),
            # senão o processo do decompilador arranca com defaults e ignora max jumptable/timeout.
            from ghidra.app.decompiler import DecompInterface
            from ghidra.util.task import TaskMonitor

            opts = _build_decompile_options(program)
            decomp = DecompInterface()
            if opts is not None:
                decomp.setOptions(opts)
            if not decomp.openProgram(program):
                result["error"] = "Falha ao abrir o programa no decompilador."
                return result

            function_manager = program.getFunctionManager()
            try:
                total_functions = int(function_manager.getFunctionCount())
            except Exception:
                total_functions = 0
            lines = []
            lines.append(f"/* Decompilado com Ghidra (PyGhidra) - {path.name} */")
            lines.append("")
            count = 0
            total_len = 0
            processed = 0
            try:
                it = function_manager.getFunctions(True)
                while it.hasNext() and count < MAX_FUNCTIONS and (
                    MAX_OUTPUT_CHARS is None or total_len < MAX_OUTPUT_CHARS
                ):
                    func = it.next()
                    name = str(func.getName()) if func.getName() else "sub"
                    addr = func.getEntryPoint()
                    addr_str = str(addr) if addr else "?"
                    try:
                        res = decomp.decompileFunction(func, DECOMPILER_TIMEOUT_SECS, TaskMonitor.DUMMY)
                        c_code = ""
                        if res.decompileCompleted():
                            df = res.getDecompiledFunction()
                            if df is not None:
                                c_code = df.getC() or ""
                        if isinstance(c_code, str):
                            c_code = c_code.strip()
                        else:
                            c_code = ""
                        if c_code:
                            lines.append(f"/* ----- {name} @ {addr_str} ----- */")
                            lines.append(c_code)
                            lines.append("")
                            count += 1
                            total_len += len(c_code)
                        else:
                            lines.append(f"/* ----- {name} @ {addr_str} ----- (decompilação falhou) */")
                            lines.append("")
                    except Exception:
                        lines.append(f"/* ----- {name} @ {addr_str} ----- (decompilação falhou) */")
                        lines.append("")
                    processed += 1
                    if progress_callback is not None and total_functions > 0:
                        try:
                            pct = max(0.0, min(100.0, (processed / total_functions) * 100.0))
                            progress_callback(pct)
                        except Exception:
                            pass
                    if MAX_OUTPUT_CHARS is not None and total_len >= MAX_OUTPUT_CHARS:
                        lines.append("/* ... (limite de tamanho atingido) */")
                        break
            finally:
                decomp.dispose()

            if count == 0:
                result["error"] = "Nenhuma função foi decompilada (pode ser binário não suportado ou sem funções reconhecidas)."
                return result

            full_text = "\n".join(lines)
            out_file.write_text(full_text, encoding="utf-8")
            result["success"] = True
            result["output_file"] = str(out_file)
            result["functions_decompiled"] = count
            if progress_callback is not None and total_functions > 0:
                try:
                    progress_callback(100.0)
                except Exception:
                    pass

            # Poupança de espaço: opcionalmente remover o projeto Ghidra (.rep/.gpr) após gerar o pseudo-C.
            try:
                if not getattr(config, "KEEP_GHIDRA_PROJECT", True):
                    try:
                        if project_dir.exists() and project_dir.is_dir():
                            shutil.rmtree(project_dir)
                    except Exception:
                        pass
                    try:
                        if project_file.exists():
                            project_file.unlink()
                    except Exception:
                        pass
            except Exception:
                pass
    except Exception as e:
        result["error"] = str(e)
        if "GHIDRA_INSTALL_DIR" in str(e) or "Ghidra" in str(e):
            result["error"] += " Defina GHIDRA_INSTALL_DIR ou instale Ghidra 12+."

    return result
