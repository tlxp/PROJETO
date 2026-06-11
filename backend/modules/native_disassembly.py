"""
Desmontagem de binários nativos (não .NET).
Gera listing em assembly (x86/x64) a partir do PE para binários sem metadados .NET.
"""

import logging
from pathlib import Path
from typing import Dict, Optional

from artifact_naming import short_stem

logger = logging.getLogger("rat_analyzer_native_disasm")

# Constantes PE (IMAGE_FILE_HEADER.Machine)
IMAGE_FILE_MACHINE_I386 = 0x014C
IMAGE_FILE_MACHINE_AMD64 = 0x8664
IMAGE_FILE_MACHINE_ARM64 = 0xAA64
# Secção executável
IMAGE_SCN_MEM_EXECUTE = 0x20000000


def disassemble_pe(file_path: str, output_path: Optional[str] = None, output_root: str = "decompiled") -> Dict:
    """
    Desmonta as secções de código de um PE (exe/dll) e grava um ficheiro .asm.
    Funciona para binários nativos (x86, x64). Não usa código fonte .NET.
    :param file_path: Caminho para o .exe ou .dll
    :param output_path: Ficheiro de saída (opcional). Se None, usa output_root/<stem>/<stem>.asm
    :param output_root: Pasta base de saída
    :return: { "success", "output_file", "error", "instructions", "arch" }
    """
    result = {"success": False, "output_file": "", "error": "", "instructions": 0, "arch": ""}
    try:
        import pefile
    except ImportError:
        result["error"] = "Módulo pefile não encontrado."
        return result
    try:
        from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_MODE_64
    except ImportError:
        result["error"] = "Módulo capstone não encontrado. Instale com: pip install capstone"
        return result

    path = Path(file_path).resolve()
    if not path.exists():
        result["error"] = f"Ficheiro não encontrado: {path}"
        return result

    try:
        pe = pefile.PE(str(path))
    except Exception as e:
        result["error"] = f"PE inválido ou não suportado: {e}"
        return result

    try:
        machine = pe.FILE_HEADER.Machine
        if machine == IMAGE_FILE_MACHINE_AMD64:
            md = Cs(CS_ARCH_X86, CS_MODE_64)
            result["arch"] = "x64"
        elif machine == IMAGE_FILE_MACHINE_I386:
            md = Cs(CS_ARCH_X86, CS_MODE_32)
            result["arch"] = "x86"
        elif machine == IMAGE_FILE_MACHINE_ARM64:
            try:
                from capstone import CS_ARCH_ARM64, CS_MODE_ARM
                md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
                result["arch"] = "ARM64"
            except Exception:
                logger.debug("Capstone ARM64 indisponível para %s", path, exc_info=True)
                result["error"] = f"Arquitetura ARM64 detetada mas capstone não suporta ou falhou."
                return result
        else:
            result["error"] = f"Arquitetura não suportada para desmontagem: Machine=0x{machine:X}"
            return result

        sstem = short_stem(path.stem)
        out_file = Path(output_path) if output_path else (Path(output_root).resolve() / sstem / f"{sstem}.asm")
        out_file.parent.mkdir(parents=True, exist_ok=True)

        lines = []
        lines.append(f"; Desmontagem: {path.name}")
        lines.append(f"; Arquitetura: {result['arch']}")
        lines.append("")
        total_instructions = 0
        section_count = 0

        for section in pe.sections:
            if not (section.Characteristics & IMAGE_SCN_MEM_EXECUTE):
                continue
            name = section.Name.decode("utf-8", errors="replace").rstrip("\x00")
            try:
                data = section.get_data()
            except Exception:
                logger.debug("Falha ao ler secção %s de %s", name, path, exc_info=True)
                continue
            if len(data) == 0:
                continue
            va = section.VirtualAddress
            lines.append(f"; --- Secção: {name} (VA=0x{va:X}, {len(data)} bytes) ---")
            lines.append("")
            for i in md.disasm(data, va):
                lines.append(f"0x{i.address:08X}:\t{i.mnemonic}\t{i.op_str}")
                total_instructions += 1
            lines.append("")
            section_count += 1
    finally:
        try:
            pe.close()
        except Exception:
            logger.debug("Falha ao fechar handle pefile em %s", path, exc_info=True)

    if total_instructions == 0:
        result["error"] = "Nenhuma secção de código executável encontrada ou desmontagem vazia."
        return result

    try:
        out_file.write_text("\n".join(lines), encoding="utf-8")
    except Exception as e:
        result["error"] = f"Erro ao escrever ficheiro: {e}"
        return result

    result["success"] = True
    result["output_file"] = str(out_file)
    result["instructions"] = total_instructions
    return result
