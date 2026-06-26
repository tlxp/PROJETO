# --- Módulo: c_code_payload ---
# Truncagem de pseudo-C/C# para payloads API e fallback de descompilação.

from __future__ import annotations

from typing import Dict, Iterable, List, Tuple

# --- Limites de truncagem do pseudo-C no payload JSON ---
MAX_CCODE_CHARS: int = 200_000
CCODE_WINDOW_RADIUS: int = 40


# --- Normaliza indicadores (trim, remove vazios/duplicados) ---
def normalize_indicators(flagged_indicators: Iterable[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for raw in flagged_indicators or []:
        s = (raw or "").strip()
        if not s or s in seen:
            continue
        seen.add(s)
        out.append(s)
    return out


# --- Funde intervalos de linhas 0-based sobrepostos ou adjacentes ---
def merge_line_windows(ranges: List[Tuple[int, int]]) -> List[Tuple[int, int]]:
    if not ranges:
        return []
    ranges.sort()
    merged: List[Tuple[int, int]] = []
    cur_start, cur_end = ranges[0]
    for s, e in ranges[1:]:
        if s <= cur_end + 1:
            cur_end = max(cur_end, e)
        else:
            merged.append((cur_start, cur_end))
            cur_start, cur_end = s, e
    merged.append((cur_start, cur_end))
    return merged


# --- Janelas de linhas em volta de cada ocorrência de indicador (0-based) ---
def build_windows_around_indicators(
    lines: List[str], indicators: List[str], radius: int
) -> List[Tuple[int, int]]:
    n = len(lines)
    ranges: List[Tuple[int, int]] = []
    if n == 0 or not indicators:
        return ranges

    for indicator in indicators:
        for i, line in enumerate(lines):
            if indicator in line:
                start = max(0, i - radius)
                end = min(n - 1, i + radius)
                ranges.append((start, end))

    return merge_line_windows(ranges)


# --- Janelas em volta de indicadores e funções suspeitas mais graves ---
def build_windows_for_payload(
    lines: List[str],
    indicators: List[str],
    flagged_functions: Iterable[dict] | None,
    radius: int,
    max_func_windows: int = 20,
) -> List[Tuple[int, int]]:
    ranges = build_windows_around_indicators(lines, indicators, radius)
    n = len(lines)
    if n == 0:
        return ranges

    sev_rank = {"CRÍTICO": 0, "ALTO": 1, "MÉDIO": 2, "BAIXO": 3}
    funcs = sorted(
        list(flagged_functions or []),
        key=lambda f: (
            sev_rank.get(str(f.get("severity") or "BAIXO").upper(), 9),
            -int(f.get("score") or 0),
            int(f.get("startLine") or 0),
        ),
    )[:max_func_windows]

    for f in funcs:
        try:
            start = max(0, int(f.get("startLine", 1)) - 1 - radius)
            end = min(n - 1, int(f.get("endLine", 1)) - 1 + radius)
        except (TypeError, ValueError):
            continue
        if start <= end:
            ranges.append((start, end))

    return merge_line_windows(ranges)


# --- Re-mapeia startLine/endLine para o pseudo-C resumido ---
def remap_flagged_functions_to_summary(
    flagged_functions: Iterable[dict] | None,
    orig_to_new: Dict[int, int],
    total_new_lines: int,
) -> List[dict]:
    out: List[dict] = []
    for raw in flagged_functions or []:
        if not isinstance(raw, dict):
            continue
        try:
            o_start = int(raw.get("startLine", 0))
            o_end = int(raw.get("endLine", 0))
        except (TypeError, ValueError):
            continue
        if o_start <= 0 or o_end <= 0 or o_end < o_start:
            continue
        mapped = [orig_to_new[i] for i in range(o_start, o_end + 1) if i in orig_to_new]
        if not mapped:
            continue
        new_ff = dict(raw)
        new_ff["startLine"] = min(mapped)
        new_ff["endLine"] = max(mapped)
        if new_ff["startLine"] <= total_new_lines:
            out.append(new_ff)
    return out


# --- Indica se a UI deve mostrar painel de resumo em vez de pseudo-C/C# ---
def should_compose_decompilation_fallback(last: dict) -> bool:
    if not last:
        return False
    if (last.get("decompilation_error_summary") or "").strip():
        return True
    ghidra = last.get("ghidra_decompilation") or {}
    return bool((ghidra.get("error") or "").strip())


# --- Texto do painel quando ILSpy falha mas há fallback Ghidra/assembly ---
def compose_fallback_descompilation_ccode(last: dict) -> str:
    ilspy = (last.get("decompilation_error_summary") or "").strip()
    lines: List[str] = ["# Descompilação para C# / pseudo-C não disponível"]

    if ilspy:
        lines.append("")
        lines.append("## .NET (ILSpy)")
        lines.append(ilspy)
    else:
        lines.append("")
        lines.append("## .NET (ILSpy)")
        lines.append("(Não aplicável ou sem resumo registado.)")

    disasm = (last.get("disassembly_file") or "").strip()
    if disasm:
        lines.append("")
        lines.append("## Assembly (fallback)")
        lines.append(f"Desmontagem concluída: {disasm}")
        lines.append("Abre o separador IL/assembly na interface para rever o listing.")

    ghidra = last.get("ghidra_decompilation") or {}
    lines.append("")
    lines.append("## Pseudo-C (Ghidra)")

    if ghidra.get("success"):
        op = ghidra.get("output_file") or ""
        nfn = ghidra.get("functions_decompiled") or 0
        lines.append(
            f"Ghidra concluiu com sucesso. Ficheiro: {op or 'N/A'} ({nfn} funções decompiladas)."
            "\nSe não vês pseudo-C acima, o carregamento do ficheiro falhou — abra o relatório ou "
            + "`decompiled/` no projeto."
        )
    elif (ghidra.get("error") or "").strip():
        err = ghidra["error"].strip()
        if len(err) > 1800:
            err = err[:1797] + "..."
        lines.append("Ghidra falhou ou não completou:")
        lines.append(err)
    else:
        lines.append(
            "Sem resultado Ghidra registado. Requisitos: variável GHIDRA_INSTALL_DIR, Ghidra 12+, "
            "`pip install pyghidra`. Passos [7a]/[7b] nos logs do analisador."
        )

    return "\n".join(lines)


# --- Trunca pseudo-C/C# para payload e re-alinha funções suspeitas ---
def summarize_c_code_payload(
    c_code: str,
    flagged_indicators: Iterable[str],
    flagged_functions: Iterable[dict] | None = None,
    max_chars: int = MAX_CCODE_CHARS,
) -> Tuple[str, List[dict]]:
    raw_flagged = [f for f in (flagged_functions or []) if isinstance(f, dict)]
    if not c_code or max_chars <= 0 or len(c_code) <= max_chars:
        return c_code, raw_flagged

    lines = c_code.splitlines()
    indicators = normalize_indicators(flagged_indicators)
    windows = build_windows_for_payload(lines, indicators, raw_flagged, CCODE_WINDOW_RADIUS)

    header = (
        f"// [RESUMO] Código truncado para o payload ({len(c_code)} > {max_chars} chars). "
        "O artefato completo está em disco no diretório do job.\n"
    )

    if windows:
        output_lines: List[str] = []
        orig_to_new: Dict[int, int] = {}

        for hl in header.splitlines():
            output_lines.append(hl)

        # --- Texto acumulado das linhas de saída ---
        def _current_text() -> str:
            return "\n".join(output_lines) + ("\n" if output_lines else "")

        for start, end in windows:
            seg_line = f"// ... linhas {start + 1}-{end + 1} ..."
            segment_lines = lines[start : end + 1]
            candidate = _current_text() + seg_line + "\n" + "\n".join(segment_lines) + "\n"
            if len(candidate) > max_chars:
                output_lines.append("// ... (truncado: limite de tamanho atingido) ...")
                summary = _current_text()
                return summary, remap_flagged_functions_to_summary(
                    raw_flagged, orig_to_new, len(output_lines)
                )

            output_lines.append(seg_line)
            for orig_i in range(start, end + 1):
                output_lines.append(lines[orig_i])
                orig_to_new[orig_i + 1] = len(output_lines)

        summary = _current_text()
        return summary, remap_flagged_functions_to_summary(
            raw_flagged, orig_to_new, len(output_lines)
        )

    # Sem janelas: truncagem simples ao início do ficheiro.
    cut = c_code[: max(0, max_chars - len(header) - 64)]
    summary = header + cut + "\n// ... (truncado) ...\n"
    output_lines = summary.splitlines()
    orig_to_new = {i + 1: i + 1 for i in range(min(len(output_lines), len(lines)))}
    return summary, remap_flagged_functions_to_summary(raw_flagged, orig_to_new, len(output_lines))


# --- Atalho: devolve apenas o pseudo-C resumido ---
def summarize_c_code(
    c_code: str,
    flagged_indicators: Iterable[str],
    flagged_functions: Iterable[dict] | None = None,
    max_chars: int = MAX_CCODE_CHARS,
) -> str:
    summarized, _ = summarize_c_code_payload(
        c_code, flagged_indicators, flagged_functions, max_chars=max_chars
    )
    return summarized
