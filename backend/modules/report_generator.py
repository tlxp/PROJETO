# --- Módulo: report_generator ---
# Geração de relatórios detalhados da análise em formato texto.

from pathlib import Path
from typing import Dict
from datetime import datetime


# --- Gera relatórios de análise em formato texto ---
class ReportGenerator:

# --- Inicialização sem estado persistente ---
    def __init__(self):
        pass

    # --- Gera relatório completo a partir dos resultados da análise ---
    def generate(self, analysis_results: Dict, output_path: Path) -> Path:
        
        report_lines = []
        
        report_lines.append("=" * 80)
        report_lines.append("RELATÓRIO DE ANÁLISE - RAT ANALYZER")
        report_lines.append("=" * 80)
        report_lines.append(f"Data/Hora: {analysis_results['timestamp']}")
        report_lines.append("")

        static = analysis_results.get('static_analysis', {})
        report_lines.append("RESUMO")
        report_lines.append("-" * 40)
        report_lines.append(f"  C&C: {len(static.get('c2_strings', []))}  |  Stealer: {len(static.get('stealer_indicators', []))}  |  Persistência: {len(static.get('persistence_indicators', []))}")
        report_lines.append(f"  Evasão: {len(static.get('evasion_techniques', []))}  |  YARA: {len(analysis_results.get('yara_matches', []))}  |  Ofuscação: {len(analysis_results.get('deobfuscation', {}).get('obfuscation_indicators', []))}")
        report_lines.append("")
        
        # Informações do ficheiro
        report_lines.append("-" * 80)
        report_lines.append("INFORMAÇÕES DO FICHEIRO")
        report_lines.append("-" * 80)
        file_info = analysis_results['file_info']
        report_lines.append(f"Nome: {file_info['filename']}")
        report_lines.append(f"Tamanho: {file_info['size']:,} bytes")
        report_lines.append(f"Extensão: {file_info['extension']}")
        report_lines.append(f"MD5: {file_info['md5']}")
        report_lines.append(f"SHA256: {file_info['sha256']}")
        report_lines.append("")
        
        report_lines.append("-" * 80)
        report_lines.append("SCORE DE RISCO")
        report_lines.append("-" * 80)
        report_lines.append(f"Score: {analysis_results['risk_score']}/100")
        report_lines.append(f"Nível: {analysis_results['risk_level']}")
        report_lines.append("")
        report_lines.append("(O score é calculado sobre o binário: análise estática, YARA e deobfuscação do .exe/.dll.")
        report_lines.append(" Não depende do código fonte descompilado; funciona mesmo quando a descompilação falha.)")
        report_lines.append("")
        
        # Detalhes do score
        if 'risk_details' in analysis_results:
            report_lines.append("Detalhes do Score:")
            details = analysis_results['risk_details']
            for factor, info in details.items():
                report_lines.append(f"  - {factor.replace('_', ' ').title()}: "
                                  f"{info['count']} ocorrências = {info['score']}/{info['max']} pontos")
            report_lines.append("")
        
        # Análise Estática
        report_lines.append("-" * 80)
        report_lines.append("ANÁLISE ESTÁTICA")
        report_lines.append("-" * 80)
        
        static = analysis_results['static_analysis']
        
        # Imports suspeitos
        report_lines.append(f"\nImports Suspeitos ({len(static.get('suspicious_imports', []))}):")
        for imp in static.get('suspicious_imports', [])[:10]:
            report_lines.append(f"  - {imp}")
        if len(static.get('suspicious_imports', [])) > 10:
            report_lines.append(f"  ... e mais {len(static.get('suspicious_imports', [])) - 10}")
        
        # Funções suspeitas
        report_lines.append(f"\nFunções Suspeitas ({len(static.get('suspicious_functions', []))}):")
        for func in static.get('suspicious_functions', [])[:10]:
            report_lines.append(f"  - {func}")
        if len(static.get('suspicious_functions', [])) > 10:
            report_lines.append(f"  ... e mais {len(static.get('suspicious_functions', [])) - 10}")
        
        # Strings C&C
        report_lines.append(f"\nStrings C&C Detectadas ({len(static.get('c2_strings', []))}):")
        for c2 in static.get('c2_strings', [])[:15]:
            report_lines.append(f"  - {c2[:80]}")
        if len(static.get('c2_strings', [])) > 15:
            report_lines.append(f"  ... e mais {len(static.get('c2_strings', [])) - 15}")

        # Indicadores de stealer
        stealers = static.get('stealer_indicators', [])
        if stealers:
            report_lines.append(f"\nIndicadores de Stealer/Credenciais ({len(stealers)}):")
            for s in stealers:
                report_lines.append(f"  - {s}")

        # Indicadores de persistência
        persist = static.get('persistence_indicators', [])
        if persist:
            report_lines.append(f"\nIndicadores de Persistência ({len(persist)}):")
            for p in persist:
                report_lines.append(f"  - {p}")
        
        # Técnicas de evasão
        report_lines.append(f"\nTécnicas de Evasão ({len(static.get('evasion_techniques', []))}):")
        for evas in static.get('evasion_techniques', [])[:10]:
            report_lines.append(f"  - {evas}")
        if len(static.get('evasion_techniques', [])) > 10:
            report_lines.append(f"  ... e mais {len(static.get('evasion_techniques', [])) - 10}")
        
        # Entropia
        if static.get('entropy'):
            report_lines.append(f"\nEntropia das Secções:")
            for section, entropy in static.get('entropy', {}).items():
                report_lines.append(f"  - {section}: {entropy}")
        
        # Indicadores de packer
        if static.get('packer_indicators'):
            report_lines.append(f"\nIndicadores de Packer ({len(static.get('packer_indicators', []))}):")
            for packer in static.get('packer_indicators', []):
                report_lines.append(f"  - {packer}")
        
        report_lines.append("")
        
        # Scan YARA
        report_lines.append("-" * 80)
        report_lines.append("SCAN YARA")
        report_lines.append("-" * 80)
        yara_matches = analysis_results['yara_matches']
        report_lines.append(f"Total de Matches: {len(yara_matches)}")
        
        for match in yara_matches:
            report_lines.append(f"\nRegra: {match['rule']}")
            report_lines.append(f"  Descrição: {match['description']}")
            report_lines.append(f"  Severidade: {match['severity']}")
            report_lines.append(f"  Tags: {', '.join(match['tags'])}")
            if match['strings']:
                report_lines.append(f"  Strings encontradas: {len(match['strings'])}")
        
        report_lines.append("")
        
        # Descompilação .NET
        if 'dotnet_decompilation' in analysis_results and analysis_results['dotnet_decompilation']:
            decomp = analysis_results['dotnet_decompilation']
            report_lines.append("-" * 80)
            report_lines.append("DESCOMPILAÇÃO .NET")
            report_lines.append("-" * 80)
            
            if decomp.get('success'):
                report_lines.append("Status: ✓ Sucesso")
                report_lines.append(f"Directório de saída: {decomp.get('output_dir', 'N/A')}")
                if decomp.get('consolidated_file'):
                    report_lines.append(f"Ficheiro consolidado: {decomp.get('consolidated_file')}")
                if decomp.get('files_count'):
                    report_lines.append(f"Ficheiros .cs gerados: {decomp.get('files_count')}")
                report_lines.append(f"Comando executado: {decomp.get('command', 'N/A')}")
            else:
                if decomp.get("error_type") == "no_managed_metadata" or decomp.get("is_dotnet") is False:
                    report_lines.append("Status: — Não aplicável (binário nativo ou .NET AOT)")
                    motivo = (
                        decomp.get("log_message")
                        or (decomp.get("error_short") or decomp.get("error", "N/A")).split("\n", 1)[0]
                    )
                    report_lines.append(f"Motivo: {motivo}")
                else:
                    report_lines.append("Status: ✗ Falhou")
                    report_lines.append(f"Erro: {decomp.get('error', 'N/A')}")
            
            report_lines.append("")
        
        # Desmontagem (assembly) para binários nativos / AOT
        disasm = analysis_results.get('native_disassembly', {})
        if disasm.get('success'):
            report_lines.append("-" * 80)
            report_lines.append("DESMONTAGEM (ASSEMBLY)")
            report_lines.append("-" * 80)
            report_lines.append("Status: ✓ Gerado (binário nativo ou .NET AOT)")
            report_lines.append(f"Ficheiro: {disasm.get('output_file', 'N/A')}")
            report_lines.append(f"Instruções: {disasm.get('instructions', 0)} | Arquitetura: {disasm.get('arch', 'N/A')}")
            report_lines.append("")
        # Decompilação Ghidra (assembly → pseudo-C)
        ghidra = analysis_results.get('ghidra_decompilation', {})
        if ghidra.get('success'):
            report_lines.append("-" * 80)
            report_lines.append("DESCOMPILAÇÃO GHIDRA (PSEUDO-C)")
            report_lines.append("-" * 80)
            report_lines.append("Status: ✓ Gerado com PyGhidra")
            report_lines.append(f"Ficheiro: {ghidra.get('output_file', 'N/A')}")
            report_lines.append(f"Funções decompiladas: {ghidra.get('functions_decompiled', 0)}")
            report_lines.append("")
        elif (ghidra.get('error') or '').strip():
            report_lines.append("-" * 80)
            report_lines.append("DESCOMPILAÇÃO GHIDRA (PSEUDO-C)")
            report_lines.append("-" * 80)
            report_lines.append("Status: ✗ Falhou")
            err = (ghidra.get('error') or '').strip()
            if len(err) > 500:
                err = err[:497] + "..."
            report_lines.append(f"Erro: {err}")
            if disasm.get('success'):
                report_lines.append(
                    f"Fallback: assembly disponível em {disasm.get('output_file', 'N/A')}."
                )
            report_lines.append("")
        
        # Deobfuscação
        report_lines.append("-" * 80)
        report_lines.append("DEOBFUSCAÇÃO")
        report_lines.append("-" * 80)
        deobf = analysis_results['deobfuscation']
        
        if deobf.get('obfuscation_indicators'):
            report_lines.append("Indicadores de Ofuscação:")
            for indicator in deobf.get('obfuscation_indicators', []):
                report_lines.append(f"  - {indicator}")
        
        if deobf.get('base64_strings'):
            report_lines.append(f"\nStrings Base64 Detectadas ({len(deobf.get('base64_strings', []))}):")
            for b64 in deobf.get('base64_strings', [])[:5]:
                report_lines.append(f"  Encoded: {b64['encoded']}")
                report_lines.append(f"  Decoded: {b64['decoded']}")
        
        if deobf.get('techniques_applied'):
            report_lines.append(f"\nTécnicas Aplicadas: {', '.join(deobf.get('techniques_applied', []))}")

        # Trechos obfuscados extraídos (ficheiros separados)
        obf_snippets = analysis_results.get("obfuscated_snippets_file") or ""
        obf_snippets_deob = analysis_results.get("obfuscated_snippets_deobfuscated_file") or ""
        obf_snippets_pseudoc = analysis_results.get("obfuscated_snippets_pseudoc_file") or ""
        obf_snippets_deob_pseudoc = analysis_results.get("obfuscated_snippets_deobfuscated_pseudoc_file") or ""
        summary = analysis_results.get("obfuscation_snippets_summary") or {}
        if obf_snippets or obf_snippets_deob or obf_snippets_pseudoc or obf_snippets_deob_pseudoc:
            report_lines.append("\nTrechos obfuscados extraídos:")
            if summary:
                total = sum(summary.values())
                parts = [f"{desc}: {n}" for desc, n in sorted(summary.items(), key=lambda x: -x[1])]
                report_lines.append(f"  Total: {total} trechos ({'; '.join(parts)})")
            if obf_snippets:
                report_lines.append(f"  Ficheiro trechos obfuscados (C#): {obf_snippets}")
            if obf_snippets_deob:
                report_lines.append(f"  Ficheiro trechos deobfuscados (C#): {obf_snippets_deob}")
            if obf_snippets_pseudoc:
                report_lines.append(f"  Ficheiro trechos obfuscados (pseudo-C): {obf_snippets_pseudoc}")
            if obf_snippets_deob_pseudoc:
                report_lines.append(f"  Ficheiro trechos deobfuscados (pseudo-C): {obf_snippets_deob_pseudoc}")
        
        report_lines.append("")
        
        # Conclusão
        report_lines.append("-" * 80)
        report_lines.append("CONCLUSÃO")
        report_lines.append("-" * 80)
        report_lines.append(f"O ficheiro apresenta um nível de risco {analysis_results['risk_level']}.")
        report_lines.append(f"Score de risco: {analysis_results['risk_score']}/100")

        if analysis_results.get("validation_sample"):
            note = (analysis_results.get("validation_note") or "").strip()
            if note:
                report_lines.append(f"\nNota: {note}")

        if analysis_results['risk_score'] >= 55 and analysis_results.get('risk_level') in ('ALTO', 'CRÍTICO'):
            report_lines.append("\n⚠️  AVISO: Este ficheiro apresenta características altamente suspeitas!")
            report_lines.append("Recomenda-se análise adicional e isolamento do sistema.")
        elif analysis_results['risk_score'] >= 35:
            report_lines.append("\n⚠️  ATENÇÃO: Este ficheiro apresenta algumas características suspeitas.")
            report_lines.append("Recomenda-se análise adicional.")
        
        report_lines.append("")
        report_lines.append("=" * 80)
        
        # Escrever relatório
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(report_lines))
        
        return output_path

