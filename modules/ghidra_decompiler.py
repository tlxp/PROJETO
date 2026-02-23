"""
Decompilação de binários nativos para pseudo-C usando PyGhidra (Ghidra).
Converte o assembly/código de máquina em código C legível (decompilador Ghidra).
Requer: Ghidra instalado e variável GHIDRA_INSTALL_DIR (ou install_dir).
"""

from pathlib import Path
from typing import Dict, Optional

# Limites para não gerar ficheiros enormes
MAX_FUNCTIONS = 500
MAX_OUTPUT_CHARS = 2 * 1024 * 1024  # 2 MB de texto C
TIMEOUT_SECONDS_PER_FUNCTION = 45


def decompile_binary_to_c(
    binary_path: str,
    output_path: Optional[str] = None,
    output_root: str = "decompiled",
    ghidra_install_dir: Optional[str] = None,
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

    try:
        import pyghidra
    except ImportError:
        result["error"] = (
            "PyGhidra não encontrado. Instale com: pip install pyghidra. "
            "Requer também Ghidra 12+ instalado e GHIDRA_INSTALL_DIR definido."
        )
        return result

    out_file = Path(output_path) if output_path else (Path(output_root).resolve() / path.stem / f"{path.stem}_decompiled.c")
    out_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        if not pyghidra.started():
            pyghidra.start(verbose=False, install_dir=ghidra_install_dir)
    except Exception as e:
        result["error"] = f"Falha ao iniciar Ghidra (verifique GHIDRA_INSTALL_DIR): {e}"
        return result

    try:
        with pyghidra.open_program(
            str(path),
            project_location=str(out_file.parent),
            project_name=f"{path.stem}_ghidra",
            analyze=True,
        ) as flat_api:
            program = flat_api.getCurrentProgram()
            from ghidra.app.decompiler.flatapi import FlatDecompilerAPI

            decomp_api = FlatDecompilerAPI(flat_api)
            function_manager = program.getFunctionManager()
            lines = []
            lines.append(f"/* Decompilado com Ghidra (PyGhidra) - {path.name} */")
            lines.append("")
            count = 0
            total_len = 0
            try:
                it = function_manager.getFunctions(True)
                while it.hasNext() and count < MAX_FUNCTIONS and total_len < MAX_OUTPUT_CHARS:
                    func = it.next()
                    name = str(func.getName()) if func.getName() else "sub"
                    addr = func.getEntryPoint()
                    addr_str = str(addr) if addr else "?"
                    try:
                        decompile_fn = getattr(decomp_api, "decompile", None) or getattr(decomp_api, "decompileFunction", None)
                        if not decompile_fn:
                            continue
                        c_code = decompile_fn(func)
                        if c_code is None:
                            c_code = ""
                        if isinstance(c_code, str) and c_code.strip():
                            lines.append(f"/* ----- {name} @ {addr_str} ----- */")
                            lines.append(c_code.strip())
                            lines.append("")
                            count += 1
                            total_len += len(c_code)
                        else:
                            # Algumas APIs devolvem objeto com getC()
                            try:
                                if hasattr(c_code, "getDecompiledFunction"):
                                    c_code = c_code.getDecompiledFunction().getC()
                                elif hasattr(c_code, "getC"):
                                    c_code = c_code.getC()
                                if c_code and str(c_code).strip():
                                    lines.append(f"/* ----- {name} @ {addr_str} ----- */")
                                    lines.append(str(c_code).strip())
                                    lines.append("")
                                    count += 1
                                    total_len += len(str(c_code))
                            except Exception:
                                pass
                    except Exception:
                        lines.append(f"/* ----- {name} @ {addr_str} ----- (decompilação falhou) */")
                        lines.append("")
                    if total_len >= MAX_OUTPUT_CHARS:
                        lines.append("/* ... (limite de tamanho atingido) */")
                        break
            finally:
                decomp_api.dispose()

            if count == 0:
                result["error"] = "Nenhuma função foi decompilada (pode ser binário não suportado ou sem funções reconhecidas)."
                return result

            out_file.write_text("\n".join(lines), encoding="utf-8")
            result["success"] = True
            result["output_file"] = str(out_file)
            result["functions_decompiled"] = count
    except Exception as e:
        result["error"] = str(e)
        if "GHIDRA_INSTALL_DIR" in str(e) or "Ghidra" in str(e):
            result["error"] += " Defina GHIDRA_INSTALL_DIR ou instale Ghidra 12+."

    return result
