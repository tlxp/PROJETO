"""
Extrai indicadores que deram flag no RAT Analyzer para destacar no pseudo-C.
Usado para realçar no código decompilado (Ghidra) as partes que acionaram
detecções (YARA, análise estática, deobfuscação).
"""

from typing import Dict, List, Set


def _is_safe_for_highlight(s: str, min_len: int = 3, max_len: int = 120) -> bool:
    """Filtra strings impróprias para highlight (binárias, muito curtas/longas)."""
    if not s or not isinstance(s, str):
        return False
    s = s.strip()
    if len(s) < min_len or len(s) > max_len:
        return False
    # Apenas strings maioritariamente imprimíveis (evitar binário)
    printable = sum(1 for c in s if c.isprintable() or c in "\n\t")
    if printable < len(s) * 0.8:
        return False
    return True


def extract_flagged_indicators(analysis_results: Dict) -> List[str]:
    """
    Extrai todos os indicadores que deram flag para destacar no pseudo-C.
    :param analysis_results: Resultados da análise (static_analysis, yara_matches, deobfuscation)
    :return: Lista de strings únicas a realçar
    """
    seen: Set[str] = set()
    indicators: List[str] = []

    def add(s: str) -> None:
        if _is_safe_for_highlight(s) and s not in seen:
            seen.add(s)
            indicators.append(s)

    # 1. YARA matches — strings encontradas
    for match in analysis_results.get("yara_matches", []):
        for s in match.get("strings", []):
            data = s.get("data", "")
            if isinstance(data, str):
                add(data)
            elif isinstance(data, bytes):
                try:
                    add(data.decode("utf-8", errors="ignore"))
                except Exception:
                    pass

    # 2. Análise estática — funções suspeitas, C2, evasão, stealer, persistência
    static = analysis_results.get("static_analysis", {})
    for name in static.get("suspicious_functions", []):
        add(str(name))
    for name in static.get("suspicious_imports", []):
        add(str(name))
    for s in static.get("c2_strings", []):
        add(str(s) if isinstance(s, str) else str(s.get("value", s)))
    for s in static.get("evasion_techniques", []):
        add(str(s) if isinstance(s, str) else str(s.get("value", s)))
    for s in static.get("stealer_indicators", []):
        add(str(s) if isinstance(s, str) else str(s.get("value", s)))
    for s in static.get("persistence_indicators", []):
        add(str(s) if isinstance(s, str) else str(s.get("value", s)))

    # 3. Deobfuscação — indicadores de ofuscação (Base64, XOR, etc.)
    deob = analysis_results.get("deobfuscation", {})
    for item in deob.get("obfuscation_indicators", []):
        if isinstance(item, dict):
            val = item.get("value") or item.get("pattern") or item.get("indicator")
            if val:
                add(str(val))
        elif isinstance(item, str):
            add(item)

    return indicators
