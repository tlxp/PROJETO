# --- Módulo: dotnet_decompiler ---
# Integração com ILSpy CLI: descompila assemblies .NET (.exe/.dll) para C#.

import logging
import os
import subprocess
import shutil
import pefile
from pathlib import Path
from typing import Optional, Dict

from artifact_naming import short_stem
import config

logger = logging.getLogger("rat_analyzer_dotnet_decompiler")


# --- Wrapper para ILSpy CLI (ilspycmd / ILSpyCmd) ---
class DotNetDecompiler:

    # --- ilspy_path: ILSpyCmd.exe ou 'ilspycmd'; output_root: pasta base de saída ---
    def __init__(self, ilspy_path: Optional[str] = None, output_root: str = "decompiled"):
        env_path = os.environ.get("ILSPY_CMD_PATH")
        
        # Se um caminho foi fornecido, verificar se existe
        if ilspy_path:
            if not Path(ilspy_path).exists():
                # Tentar encontrar automaticamente
                found_path = self._find_ilspy()
                if found_path:
                    self.ilspy_path = found_path
                else:
                    self.ilspy_path = ilspy_path  # Manter o fornecido para mostrar erro claro
            else:
                self.ilspy_path = ilspy_path
        elif env_path:
            self.ilspy_path = env_path
        else:
            # Tentar encontrar automaticamente
            found_path = self._find_ilspy()
            self.ilspy_path = found_path or "ilspycmd"
        
        self.output_root = Path(output_root).resolve()
        self.output_root.mkdir(parents=True, exist_ok=True)
    
    # --- Procura ILSpy no PATH ou em locais comuns no Windows ---
    def _find_ilspy(self) -> Optional[str]:
        # Verificar se está no PATH
        ilspy_in_path = shutil.which("ilspycmd")
        if ilspy_in_path:
            return ilspy_in_path
        
        # Verificar locais comuns no Windows
        common_paths = [
            Path.home() / ".dotnet" / "tools" / "ilspycmd.exe",
            Path("C:/Program Files/ILSpy/ILSpyCmd.exe"),
            Path("C:/Program Files (x86)/ILSpy/ILSpyCmd.exe"),
        ]
        
        for path in common_paths:
            if path.exists():
                return str(path)
        
        return None

    # --- Verifica disponibilidade do comando ILSpy CLI ---
    def is_available(self) -> bool:
        # Verificar se o caminho existe
        if Path(self.ilspy_path).exists():
            return True
        
        if shutil.which(self.ilspy_path):
            return True
        
        # Tentar executar para verificar
        try:
            subprocess.run(
                [self.ilspy_path, "--version"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=5,
            )
            return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False
    
    # --- Verifica CLR header (assembly .NET válido) ---
    def _is_dotnet_assembly(self, assembly_path: Path) -> bool:
        pe = None
        try:
            pe = pefile.PE(str(assembly_path))
            # Verificar se tem CLR header (indicador de assembly .NET)
            if hasattr(pe, 'OPTIONAL_HEADER'):
                if hasattr(pe.OPTIONAL_HEADER, 'DATA_DIRECTORY'):
                    clr_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[14]  # IMAGE_DIRECTORY_ENTRY_COM_DESCRIPTOR
                    if clr_dir.VirtualAddress != 0:
                        return True
            return False
        except Exception:
            logger.debug("Falha ao verificar metadados .NET em %s", assembly_path, exc_info=True)
            return False
        finally:
            if pe is not None:
                try:
                    pe.close()
                except Exception:
                    logger.debug("Falha ao fechar pefile em %s", assembly_path, exc_info=True)

    @staticmethod
    # --- Mensagens para PE sem metadados .NET (nativo, AOT) ---
    def _no_managed_metadata_result() -> Dict[str, str]:
        error_short = (
            "Este ficheiro não contém metadados .NET (ILSpy não consegue descompilar). "
            "Pode ser: executável nativo (C/C++), ou .NET compilado com Native AOT.\n\n"
            "A análise estática (strings, imports, YARA, score) corre sempre sobre o PE. "
            "Em seguida o pipeline tenta assembly (Capstone) e pseudo-C (Ghidra) no mesmo binário "
            "se GHIDRA_INSTALL_DIR/pyghidra estiverem configurados — ver também o separador IL/assembly."
        )
        return {
            "error_type": "no_managed_metadata",
            "error_short": error_short,
            "log_message": (
                "Sem metadados .NET no PE (binário nativo ou AOT); descompilação ILSpy não aplicável."
            ),
        }

    @staticmethod
    # --- Reduz stderr do ILSpy a uma linha legível ---
    def _summarize_ilspy_error(error_msg: str, returncode: int) -> str:
        lines = [ln.strip() for ln in error_msg.splitlines() if ln.strip()]
        headline = ""
        for ln in lines:
            if "Exception:" in ln:
                headline = ln.split("Exception:", 1)[-1].strip()
                break
            if ln.startswith("Erro:"):
                headline = ln[5:].strip()
                break
            if ln.startswith("Error:"):
                headline = ln[6:].strip()
                break
        if not headline and lines:
            headline = lines[0]
        if headline:
            return f"ILSpy retornou código {returncode}: {headline}"
        return f"ILSpy retornou código {returncode}."

    # --- Descompila assembly .NET via ILSpy CLI ---
    def decompile(self, assembly_path: str) -> Dict:
        assembly = Path(assembly_path)
        result: Dict = {
            "success": False,
            "assembly": str(assembly),
            "output_dir": "",
            "command": "",
            "error": "",
            "is_dotnet": False,
        }

        assembly = assembly.resolve()
        if not assembly.exists():
            result["error"] = f"Assembly não encontrado: {assembly}"
            return result

        result["is_dotnet"] = self._is_dotnet_assembly(assembly)

        # Cada ficheiro analisado terá o seu próprio subdiretório (caminhos absolutos)
        output_dir = (self.output_root / short_stem(assembly.stem)).resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        result["output_dir"] = str(output_dir)

        if not result["is_dotnet"]:
            meta = self._no_managed_metadata_result()
            result.update(meta)
            result["skipped"] = True
            result["error"] = meta["error_short"]
            return result

# --- Grava ficheiro de erro na pasta de saída ---
        def _write_erro_pasta(msg: str) -> None:
            # *Ficheiro na pasta de saída explica o erro quando descompilação falha*
            try:
                (output_dir / "_erro_descompilacao.txt").write_text(
                    "Descompilação não concluída.\n\n" + msg,
                    encoding="utf-8",
                )
            except OSError:
                logger.debug("Falha ao escrever _erro_descompilacao.txt em %s", output_dir, exc_info=True)

        # Verificar se o ILSpy está disponível
        if not self.is_available():
            found_path = self._find_ilspy()
            if found_path:
                self.ilspy_path = found_path
            else:
                result["error"] = (
                    f"ILSpyCmd não encontrado no caminho: {self.ilspy_path}\n"
                    f"Por favor, instale o ILSpy CLI ou forneça o caminho correto com --ilspy-path.\n"
                    f"Instalação: dotnet tool install -g ilspycmd"
                )
                _write_erro_pasta(result["error"])
                return result

        # Comando ILSpy CLI: -p cria um ficheiro .cs por tipo (ex.: Program.cs)
        cmd = [
            self.ilspy_path,
            "-p",
            "-o",
            str(output_dir),
            str(assembly),
        ]
        result["command"] = " ".join(cmd)
        result["output_dir"] = str(output_dir)

        try:
            completed = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=60,  # Timeout de 60 segundos
            )

            if completed.returncode != 0:
                error_msg = completed.stderr.strip() or completed.stdout.strip()
                summary = self._summarize_ilspy_error(error_msg, completed.returncode)
                result["log_message"] = summary
                result["error"] = summary
                # Runtime em falta (ilspycmd antigo pede .NET 6; máquina só tem 8, etc.)
                if (
                    "install or update .NET" in error_msg
                    or "Microsoft.NETCore.App" in error_msg
                    or ("Framework:" in error_msg and ".NETCore.App" in error_msg)
                ):
                    result["error_type"] = "missing_dotnet_runtime"
                    result["error_short"] = (
                        "O ILSpy CLI (ilspycmd) precisa de um runtime .NET que não está instalado — "
                        "versões antigas do pacote pedem .NET 6 embora tenhas SDK/.NET 8.\n\n"
                        "Opções:\n"
                        "• Instalar runtime .NET 6 (x64): https://dotnet.microsoft.com/download/dotnet/6.0\n"
                        "• Ou atualizar a ferramenta para uma versão que use .NET 8:\n"
                        "  dotnet tool update -g ilspycmd --version 10.0.0.8330\n\n"
                        "Depois reinicie o backend Python."
                    )
                    result["log_message"] = result["error_short"].split("\n", 1)[0]
                    result["error"] = result["error_short"]
                # Mensagem curta para a GUI (ficheiro nativo ou AOT)
                elif completed.returncode == 70 or "managed metadata" in error_msg or "MetadataFileNotSupportedException" in error_msg:
                    meta = self._no_managed_metadata_result()
                    result.update(meta)
                    result["is_dotnet"] = False
                # Escrever versão legível na pasta (resumo primeiro)
                msg_para_pasta = result.get("error_short", result["error"])
                detail = error_msg if error_msg and error_msg not in msg_para_pasta else ""
                pasta_body = msg_para_pasta
                if detail:
                    pasta_body += "\n\n--- Detalhe técnico ---\n\n" + detail
                _write_erro_pasta(pasta_body)
                return result

            # Ficheiros .cs gerados pelo ILSpy (excluir o nosso consolidado)
            consolidated_name = f"{short_stem(assembly.stem)}.decompiled.cs"
            cs_files = [f for f in output_dir.rglob("*.cs") if f.name != consolidated_name]
            if not cs_files:
                result["error"] = (
                    f"ILSpy executou com sucesso, mas nenhum ficheiro .cs foi gerado. "
                    f"O ficheiro pode estar vazio, corrompido ou não ser um assembly .NET (ex.: Native AOT)."
                )
                _write_erro_pasta(result["error"])
                return result

            # Consolidar todos os ficheiros .cs num único ficheiro .decompiled.cs
            consolidated_file = output_dir / f"{short_stem(assembly.stem)}.decompiled.cs"
            self._consolidate_cs_files(cs_files, consolidated_file)
            result["consolidated_file"] = str(consolidated_file)
            result["files_count"] = len(cs_files)

            # Poupança de espaço: por defeito, manter apenas o consolidado (opcional).
            # Mantemos a árvore ILSpy apenas se config.KEEP_ILSPY_TREE estiver ativo.
            try:
                if not getattr(config, "KEEP_ILSPY_TREE", True):
                    for f in output_dir.rglob("*.cs"):
                        if f.resolve() == consolidated_file.resolve():
                            continue
                        try:
                            f.unlink()
                        except OSError:
                            logger.debug("Falha ao remover ficheiro ILSpy intermédio: %s", f, exc_info=True)
                    # Remover diretórios vazios
                    for d in sorted([p for p in output_dir.rglob("*") if p.is_dir()], key=lambda p: len(str(p)), reverse=True):
                        try:
                            if not any(d.iterdir()):
                                d.rmdir()
                        except OSError:
                            logger.debug("Falha ao remover diretório vazio: %s", d, exc_info=True)
            except Exception:
                logger.debug("Falha na limpeza da árvore ILSpy em %s", output_dir, exc_info=True)

            result["success"] = True
            return result
        except FileNotFoundError:
            found_path = self._find_ilspy()
            if found_path:
                result["error"] = (
                    f"ILSpyCmd não encontrado no caminho fornecido, mas foi encontrado em: {found_path}\n"
                    f"Por favor, use: --ilspy-path \"{found_path}\""
                )
            else:
                result["error"] = (
                    f"ILSpyCmd/ilspycmd não encontrado no caminho: {self.ilspy_path}\n"
                    f"Configure ILSPY_CMD_PATH ou passe --ilspy-path com o caminho correto.\n"
                    f"Instalação: dotnet tool install -g ilspycmd"
                )
            try:
                (output_dir / "_erro_descompilacao.txt").write_text("Descompilação não concluída.\n\n" + result["error"], encoding="utf-8")
            except OSError:
                logger.debug("Falha ao escrever erro ILSpy (not found) em %s", output_dir, exc_info=True)
            return result
        except subprocess.TimeoutExpired:
            result["error"] = "ILSpy demorou mais de 60 segundos e foi interrompido."
            logger.warning("Timeout ILSpy ao descompilar %s", assembly)
            try:
                (output_dir / "_erro_descompilacao.txt").write_text("Descompilação não concluída.\n\n" + result["error"], encoding="utf-8")
            except OSError:
                logger.debug("Falha ao escrever erro ILSpy (timeout) em %s", output_dir, exc_info=True)
            return result
        except Exception as e:
            result["error"] = f"Erro inesperado: {str(e)}"
            logger.exception("Erro inesperado ao descompilar %s", assembly)
            try:
                (output_dir / "_erro_descompilacao.txt").write_text("Descompilação não concluída.\n\n" + result["error"], encoding="utf-8")
            except OSError:
                logger.debug("Falha ao escrever erro ILSpy (inesperado) em %s", output_dir, exc_info=True)
            return result
    
    # --- Consolida todos os ficheiros .cs num único ficheiro ---
    def _consolidate_cs_files(self, cs_files: list, output_file: Path):
        with open(output_file, 'w', encoding='utf-8') as out:
            out.write(f"// Código C# descompilado consolidado\n")
            out.write(f"// Total de ficheiros: {len(cs_files)}\n\n")
            
            for cs_file in sorted(cs_files):
                out.write(f"\n{'='*80}\n")
                try:
                    rel = cs_file.relative_to(output_file.parent)
                except ValueError:
                    rel = cs_file.name
                out.write(f"// Ficheiro: {rel}\n")
                out.write(f"{'='*80}\n\n")
                
                try:
                    with open(cs_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        out.write(content)
                        out.write("\n\n")
                except Exception as e:
                    out.write(f"// Erro ao ler ficheiro: {e}\n\n")


