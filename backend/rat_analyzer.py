#!/usr/bin/env python3
"""
RAT Analyzer - Ferramenta de Análise Automática de DLLs e Executáveis
Projeto de Licenciatura - Detecção de Remote Access Trojans
"""

import argparse
import json
import sys
import os
from pathlib import Path
from datetime import datetime

import config
from modules.static_analyzer import StaticAnalyzer
from modules.yara_scanner import YaraScanner
from modules.deobfuscator import Deobfuscator
from modules.obfuscation_snippet_extractor import (
    extract_and_write_snippets,
    extract_and_write_snippets_from_content,
)
from modules.risk_scorer import RiskScorer
from modules.report_generator import ReportGenerator
from modules.dotnet_decompiler import DotNetDecompiler
from modules.native_disassembly import disassemble_pe
from modules.pseudo_c_highlighter import extract_flagged_indicators, build_flagged_functions
try:
    from modules.ghidra_decompiler import decompile_binary_to_c
except ImportError:
    decompile_binary_to_c = None


class RATAnalyzer:
    """Classe principal que orquestra toda a análise de RATs"""
    
    def __init__(
        self,
        target_file: str,
        output_dir: str | None = None,
        use_dotnet_decompiler: bool = False,
        ilspy_path: str | None = None,
        log_callback=None,
    ):
        self.target_file = Path(target_file)
        self.output_dir = Path(output_dir or str(config.REPORTS_DIR))
        self.output_dir.mkdir(exist_ok=True)
        
        if not self.target_file.exists():
            raise FileNotFoundError(f"Ficheiro não encontrado: {target_file}")
        
        # Inicializar módulos
        self.static_analyzer = StaticAnalyzer()
        self.yara_scanner = YaraScanner(rules_dir=str(config.YARA_RULES_DIR))
        self.deobfuscator = Deobfuscator()
        self.risk_scorer = RiskScorer()
        self.report_generator = ReportGenerator()
        self.use_dotnet_decompiler = use_dotnet_decompiler
        self.dotnet_decompiler = DotNetDecompiler(
            ilspy_path=ilspy_path,
            output_root=str(config.DECOMPILED_DIR),
        )
        self._log_callback = log_callback
        
        # Resultados da análise
        self.analysis_results = {
            "file_info": {},
            "static_analysis": {},
            "yara_matches": [],
            "deobfuscation": {},
            "dotnet_decompilation": {},
            "risk_score": 0,
            "risk_level": "",
            "timestamp": datetime.now().isoformat(),
        }
    
    def _log(self, msg: str) -> None:
        """Imprime ou envia via callback para logs em tempo real."""
        if self._log_callback is not None:
            try:
                self._log_callback(msg)
            except Exception:
                print(msg, flush=True)
        else:
            print(msg, flush=True)

    def analyze(self):
        """Executa a análise completa do ficheiro"""
        self._log(f"[*] Iniciando análise de: {self.target_file.name}")
        self._log("[1/7] Extraindo informações do ficheiro...")
        self.analysis_results["file_info"] = self._get_file_info()
        self._log("      OK.")

        # 2. Se pedido, descompilar .NET com ILSpy
        if self.use_dotnet_decompiler:
            self._log("[2/7] Descompilação .NET (ILSpy) — pode demorar 1-2 min...")
            decomp_result = self.dotnet_decompiler.decompile(str(self.target_file))
            self.analysis_results["dotnet_decompilation"] = decomp_result
            if not decomp_result.get("success"):
                self._log(f"[!] AVISO: Falha na descompilação .NET: {decomp_result.get('error')}")
            else:
                self._log(f"[+] Código C# descompilado para: {decomp_result.get('output_dir')}")

        # 3. Análise estática
        self._log("[3/7] Análise estática (strings, imports, indicadores)...")
        self.analysis_results["static_analysis"] = self.static_analyzer.analyze(
            str(self.target_file)
        )
        self._log("      OK.")

        # 4. Deobfuscação (se necessário)
        self._log("[4/7] Deobfuscação (Base64, XOR, ofuscação)...")
        self.analysis_results["deobfuscation"] = self.deobfuscator.deobfuscate(
            str(self.target_file)
        )
        self._log("      OK.")
        self._log("      OK.")

        # 5. Scan YARA
        self._log("[5/7] Scan YARA (regras RAT/C2/evasão)...")
        self.analysis_results["yara_matches"] = self.yara_scanner.scan(
            str(self.target_file)
        )
        self._log("      OK.")

        # 6. Cálculo do score de risco
        self._log("[6/7] Cálculo do score de risco...")
        risk_assessment = self.risk_scorer.calculate_risk(
            self.analysis_results["static_analysis"],
            self.analysis_results["yara_matches"],
            self.analysis_results["deobfuscation"],
        )
        self.analysis_results["risk_score"] = risk_assessment["score"]
        self.analysis_results["risk_level"] = risk_assessment["level"]
        self.analysis_results["risk_details"] = risk_assessment["details"]
        
        # 6. Se houve descompilação .NET, aplicar deobfuscação ao código fonte; senão, tentar desmontagem (assembly) para binários nativos
        decomp = self.analysis_results.get("dotnet_decompilation", {})
        consolidated_file = decomp.get("consolidated_file") or ""
        decompiled_dir = decomp.get("output_dir") or ""
        deobfuscated_file = ""
        obfuscated_snippets_file = ""
        obfuscated_snippets_deobfuscated_file = ""
        obfuscation_snippets_summary: dict = {}
        self.analysis_results["obfuscated_snippets_file"] = ""
        self.analysis_results["obfuscated_snippets_deobfuscated_file"] = ""
        self.analysis_results["obfuscated_snippets_pseudoc_file"] = ""
        self.analysis_results["obfuscated_snippets_deobfuscated_pseudoc_file"] = ""
        self.analysis_results["obfuscation_snippets_summary"] = {}
        decompilation_error_summary = ""
        disassembly_file = ""
        decompiled_c_file = ""
        obfuscated_snippets_pseudoc_file = ""
        obfuscated_snippets_deobfuscated_pseudoc_file = ""
        if not decomp.get("success") and decomp.get("error"):
            decompilation_error_summary = decomp.get("error_short") or decomp.get("error", "")
            if len(decompilation_error_summary) > 280:
                decompilation_error_summary = decompilation_error_summary[:277] + "..."
        if decomp.get("success") and consolidated_file and Path(consolidated_file).exists():
            # Extrair trechos obfuscados para ficheiros separados (antes de deobfuscar o ficheiro inteiro)
            output_dir_snippets = Path(consolidated_file).parent
            obf_path, deob_path, summary = extract_and_write_snippets(
                consolidated_file,
                output_dir_snippets,
                self.target_file.stem,
                self.deobfuscator.deobfuscate_content,
            )
            if obf_path:
                obfuscated_snippets_file = obf_path
                obfuscated_snippets_deobfuscated_file = deob_path
                obfuscation_snippets_summary = dict(summary)
                n = sum(summary.values())
                self._log(
                    f"[+] Trechos obfuscados: {n} extraídos; "
                    f"obfuscado → {obf_path}; deobfuscado → {deob_path}"
                )
            self.analysis_results["obfuscated_snippets_file"] = obfuscated_snippets_file
            self.analysis_results["obfuscated_snippets_deobfuscated_file"] = obfuscated_snippets_deobfuscated_file
            self.analysis_results["obfuscation_snippets_summary"] = obfuscation_snippets_summary

            print("[*] A aplicar deobfuscação ao código descompilado...")
            out_deob = Path(consolidated_file).parent / (self.target_file.stem + ".deobfuscated.cs")
            do_result = self.deobfuscator.deobfuscate_source(consolidated_file, str(out_deob))
            if do_result.get("success"):
                deobfuscated_file = do_result.get("output_file", "")
                if do_result.get("base64_decoded"):
                    print(f"[+] Código desobfuscado guardado: {deobfuscated_file} ({do_result['base64_decoded']} Base64 decodificados)")
        else:
            # Binário nativo ou .NET AOT: assembly e Ghidra diretamente no binário original (sem deobfuscação binária)
            self._log("[7a] Desmontagem (assembly) do binário...")
            out_asm = str(config.DECOMPILED_DIR / self.target_file.stem / f"{self.target_file.stem}.asm")
            disasm_result = disassemble_pe(str(self.target_file), output_path=out_asm, output_root=str(config.DECOMPILED_DIR))
            self.analysis_results["native_disassembly"] = disasm_result
            if disasm_result.get("success"):
                disassembly_file = disasm_result.get("output_file", "")
                self._log(f"[+] Assembly guardado: {disassembly_file} ({disasm_result.get('instructions', 0)} instruções, {disasm_result.get('arch', '')})")
            elif disasm_result.get("error"):
                self._log(f"[!] Desmontagem não disponível: {disasm_result['error']}")
            decompiled_c_file = ""
            if decompile_binary_to_c:
                self._log("[7b] Decompilação para pseudo-C (Ghidra) — pode demorar vários minutos...")
                ghidra_dir = os.environ.get("GHIDRA_INSTALL_DIR")
                out_c = str(config.DECOMPILED_DIR / self.target_file.stem / f"{self.target_file.stem}_decompiled.c")
                try:
                    ghidra_result = decompile_binary_to_c(
                        str(self.target_file),
                        output_path=out_c,
                        output_root=str(config.DECOMPILED_DIR),
                        ghidra_install_dir=ghidra_dir,
                        progress_callback=lambda pct: self._log(f"[GHIDRA_PROGRESS] {pct:.1f}"),
                    )
                    self.analysis_results["ghidra_decompilation"] = ghidra_result
                    if ghidra_result.get("success"):
                        decompiled_c_file = ghidra_result.get("output_file", "")
                        self._log(f"[+] Pseudo-C guardado: {decompiled_c_file} ({ghidra_result.get('functions_decompiled', 0)} funções)")
                        # Extrair trechos obfuscados do pseudo-C
                        try:
                            content_c = Path(decompiled_c_file).read_text(encoding="utf-8", errors="replace")
                            out_dir_c = Path(decompiled_c_file).parent
                            obf_p, deob_p, sum_p = extract_and_write_snippets_from_content(
                                content_c,
                                decompiled_c_file,
                                out_dir_c,
                                f"{self.target_file.stem}_pseudoc",
                                self.deobfuscator.deobfuscate_content,
                            )
                            if obf_p:
                                obfuscated_snippets_pseudoc_file = obf_p
                                obfuscated_snippets_deobfuscated_pseudoc_file = deob_p
                                for k, v in sum_p.items():
                                    obfuscation_snippets_summary[k] = obfuscation_snippets_summary.get(k, 0) + v
                                self.analysis_results["obfuscation_snippets_summary"] = obfuscation_snippets_summary
                                self.analysis_results["obfuscated_snippets_pseudoc_file"] = obf_p
                                self.analysis_results["obfuscated_snippets_deobfuscated_pseudoc_file"] = deob_p
                                self._log(f"[+] Trechos obfuscados (pseudo-C): {obf_p}")
                        except Exception as e:
                            self._log(f"[!] Extração de trechos pseudo-C falhou: {e}")
                    elif ghidra_result.get("error"):
                        self._log(f"[!] Ghidra: {ghidra_result['error'][:80]}...")
                except Exception as e:
                    self._log(f"[!] Ghidra decompilation falhou: {e}")
            else:
                self._log("[!] PyGhidra não disponível; instale pyghidra e Ghidra 12+ para pseudo-C.")

        # 7. Gerar relatório (após descompilação/desmontagem para incluir assembly no relatório)
        self._log("[7/7] A gerar relatório...")
        report_path = self.report_generator.generate(
            self.analysis_results,
            self.output_dir
            / f"report_{self.target_file.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
        )

        if decompiled_c_file and not Path(decompiled_c_file).exists():
            decompiled_c_file = ""
        # Guardar last_analysis.json para a GUI / API poder mostrar "Ver código" / "Ver assembly" / "Ver C"
        flagged_indicators = extract_flagged_indicators(self.analysis_results) if decompiled_c_file else []
        flagged_functions = (
            build_flagged_functions(
                Path(decompiled_c_file).read_text(encoding="utf-8", errors="replace"),
                self.analysis_results,
                flagged_indicators,
            )
            if decompiled_c_file
            else []
        )
        deobf = self.analysis_results.get("deobfuscation", {})
        obfuscation_indicators = deobf.get("obfuscation_indicators", []) or []

        _ghidra = self.analysis_results.get("ghidra_decompilation") or {}
        ghidra_snapshot = {
            "success": bool(_ghidra.get("success")),
            "error": ((_ghidra.get("error") or "")[:2500]),
            "output_file": _ghidra.get("output_file") or "",
            "functions_decompiled": int(_ghidra.get("functions_decompiled") or 0),
        }

        last_analysis = {
            "target_file": str(self.target_file),
            "report_path": str(report_path),
            "decompiled_dir": decompiled_dir or (str(Path(disassembly_file).parent) if disassembly_file else ""),
            "consolidated_file": consolidated_file,
            "deobfuscated_file": deobfuscated_file,
            "obfuscated_snippets_file": obfuscated_snippets_file,
            "obfuscated_snippets_deobfuscated_file": obfuscated_snippets_deobfuscated_file,
            "obfuscated_snippets_pseudoc_file": obfuscated_snippets_pseudoc_file,
            "obfuscated_snippets_deobfuscated_pseudoc_file": obfuscated_snippets_deobfuscated_pseudoc_file,
            "obfuscation_snippets_summary": obfuscation_snippets_summary,
            "obfuscation_indicators": obfuscation_indicators,
            "disassembly_file": disassembly_file,
            "decompiled_c_file": decompiled_c_file,
            "decompilation_error_summary": decompilation_error_summary,
            "ghidra_decompilation": ghidra_snapshot,
            "flagged_indicators": flagged_indicators,
            "flagged_functions": flagged_functions,
        }
        last_path = self.output_dir / "last_analysis.json"
        try:
            with open(last_path, "w", encoding="utf-8") as f:
                json.dump(last_analysis, f, indent=2, ensure_ascii=False)
        except Exception as e:
            self._log(f"[!] Aviso: não foi possível guardar last_analysis.json: {e}")
        
        self._log("")
        self._log("[+] Análise concluída!")
        self._log(f"[+] Score de Risco: {self.analysis_results['risk_score']}/100 ({self.analysis_results['risk_level']})")
        self._log(f"[+] Relatório salvo em: {report_path}")
        
        return self.analysis_results
    
    def _get_file_info(self):
        """Extrai informações básicas do ficheiro"""
        stat = self.target_file.stat()
        return {
            'filename': self.target_file.name,
            'size': stat.st_size,
            'extension': self.target_file.suffix.lower(),
            'md5': self._calculate_md5(),
            'sha256': self._calculate_sha256()
        }
    
    def _calculate_md5(self):
        """Calcula hash MD5 do ficheiro"""
        import hashlib
        hash_md5 = hashlib.md5()
        with open(self.target_file, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    
    def _calculate_sha256(self):
        """Calcula hash SHA256 do ficheiro"""
        import hashlib
        hash_sha256 = hashlib.sha256()
        with open(self.target_file, "rb") as b:
            for chunk in iter(lambda: b.read(4096), b""):
                hash_sha256.update(chunk)
        return hash_sha256.hexdigest()


def main():
    parser = argparse.ArgumentParser(
        description='RAT Analyzer - Ferramenta de Análise Automática de DLLs e Executáveis'
    )
    parser.add_argument('file', help='Caminho para o ficheiro .exe ou .dll a analisar')
    parser.add_argument('-o', '--output', default=None,
                        help='Directório de saída para relatórios (padrão: reports/)')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Modo verboso')
    parser.add_argument('--dotnet', action='store_true',
                       help='Tratar o ficheiro como assembly .NET e descompilar com ILSpy CLI')
    parser.add_argument('--ilspy-path', default=None,
                       help='Caminho para ILSpyCmd.exe / ilspycmd (se não estiver no PATH)')
    
    args = parser.parse_args()
    
    try:
        analyzer = RATAnalyzer(
            args.file,
            args.output,
            use_dotnet_decompiler=args.dotnet,
            ilspy_path=args.ilspy_path,
        )
        results = analyzer.analyze()
        
        if args.verbose:
            print("\n" + "="*60)
            print("DETALHES DA ANÁLISE")
            print("="*60)
            print(f"Ficheiro: {results['file_info']['filename']}")
            print(f"Tamanho: {results['file_info']['size']} bytes")
            print(f"MD5: {results['file_info']['md5']}")
            print(f"SHA256: {results['file_info']['sha256']}")
            print(f"\nScore de Risco: {results['risk_score']}/100")
            print(f"Nível de Risco: {results['risk_level']}")
            print(f"\nMatches YARA: {len(results['yara_matches'])}")
            if results['yara_matches']:
                for match in results['yara_matches']:
                    print(f"  - {match['rule']}: {match['description']}")
        
        return 0
    except Exception as e:
        print(f"[!] Erro: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

