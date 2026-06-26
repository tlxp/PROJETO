# --- Módulo: pseudo_c_highlighter ---
# Extrai indicadores com flag e realça funções suspeitas no pseudo-C (Ghidra).

from typing import Dict, List, Set, Any, Tuple


# --- Filtra strings impróprias para highlight ---
def _is_safe_for_highlight(s: str, min_len: int = 3, max_len: int = 120) -> bool:
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


# --- Extrai indicadores com flag para destacar no pseudo-C ---
def extract_flagged_indicators(analysis_results: Dict) -> List[str]:
    seen: Set[str] = set()
    indicators: List[str] = []

# --- Acumula indicador seguro sem duplicar ---
    def add(s: str) -> None:
        if _is_safe_for_highlight(s) and s not in seen:
            seen.add(s)
            indicators.append(s)

    # 1) YARA matches — strings encontradas
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

    # 2) Análise estática — funções suspeitas, C2, evasão, stealer, persistência
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

    # 3) Deobfuscação — indicadores de ofuscação (Base64, XOR, etc.)
    deob = analysis_results.get("deobfuscation", {})
    for item in deob.get("obfuscation_indicators", []):
        if isinstance(item, dict):
            val = item.get("value") or item.get("pattern") or item.get("indicator")
            if val:
                add(str(val))
        elif isinstance(item, str):
            add(item)

    return indicators


# --- Heurística para extrair funções do pseudo-C (name, startLine, endLine) ---
def _parse_pseudo_c_functions(c_source: str) -> List[Dict[str, Any]]:
    import re

    lines = c_source.split("\n")
    results: List[Dict[str, Any]] = []

    # A Ghidra frequentemente coloca o "{" numa linha separada da assinatura:
    #
    #   void FUN_10001020(void)
    #
    #   {
    #     ...
    #   }
    #
    # Por isso, suportamos:
    #   - assinatura + "{" na mesma linha
    #   - assinatura numa linha, "{" 1-3 linhas depois (ignorando vazios/comentários)
    #
    # Regex permissivo para assinatura *sem* exigir "{"
    sig_re = re.compile(
        r"""
        ^\s*
        (?:
          (?:[A-Za-z_][\w\s\*\(\)]*)     # tipo de retorno / atributos
          \s+
        )?
        (?P<name>[A-Za-z_]\w*)           # nome da função
        \s*
        \(
          [^;]*                          # parâmetros (não deve conter ';' de protótipo)
        \)
        \s*
        (?:\{)?                          # "{" opcional (pode vir na linha seguinte)
        \s*$
        """,
        re.VERBOSE,
    )

    control_keywords = {
        "if",
        "for",
        "while",
        "switch",
        "catch",
        "return",
        "sizeof",
    }

    balance = 0
    current_start: int | None = None
    current_name: str | None = None

    # (name, startLine, maxLineToFindOpenBrace)
    pending_sig: tuple[str, int, int] | None = None

    banner_re = re.compile(
        r"^\s*/\*\s*-{2,}\s*(?P<name>[A-Za-z_]\w*)\s*@",
        re.IGNORECASE,
    )

# --- Ignora tokens entre assinatura e chaveta ---
    def _is_ignorable_between_sig_and_brace(raw: str) -> bool:
        t = (raw or "").strip()
        if not t:
            return True
        if t.startswith("/*") or t.startswith("*") or t.startswith("//"):
            return True
        return False

# --- Expande início com banner Ghidra acima ---
    def _expand_start_with_banner(func_name: str, start_line: int) -> int:
        # *Inclui linha de banner da Ghidra imediatamente acima da assinatura*
        if start_line <= 1:
            return start_line
        # Olhar 1-2 linhas acima da assinatura (alguns dumps têm uma linha vazia extra).
        for back in (1, 2):
            prev_idx = start_line - 1 - back
            if prev_idx < 0:
                continue
            prev = lines[prev_idx]
            m = banner_re.match(prev or "")
            if m and (m.group("name") or "") == func_name:
                return start_line - back
        return start_line

    for idx, line in enumerate(lines):
        line_no = idx + 1
        stripped = line.strip()

        # 1) Se estamos fora de qualquer bloco, tentar detetar assinatura
        if balance == 0 and current_start is None:
            m = sig_re.match(line)
            if m:
                name = (m.group("name") or "").strip()
                if name and name not in control_keywords:
                    if "{" in line:
                        # Função inicia nesta linha
                        current_start = _expand_start_with_banner(name, line_no)
                        current_name = name
                        balance += line.count("{") - line.count("}")
                        if balance == 0:
                            # Caso patológico: abre/fecha na mesma linha
                            results.append(
                                {"name": current_name, "startLine": current_start, "endLine": line_no}
                            )
                            current_start = None
                            current_name = None
                        continue
                    # Assinatura sem "{": aguardar a chaveta em linhas seguintes
                    # Permitir até ~12 linhas depois da assinatura para encontrar "{"
                    # (a Ghidra às vezes insere várias linhas vazias).
                    pending_sig = (name, line_no, line_no + 12)

        # 2) Se temos uma assinatura pendente, procurar o "{"
        if balance == 0 and current_start is None and pending_sig is not None:
            pname, pstart, max_line = pending_sig
            if line_no != pstart:
                if line_no > max_line:
                    pending_sig = None
                elif _is_ignorable_between_sig_and_brace(line):
                    pending_sig = (pname, pstart, max_line)
                elif stripped.startswith("{"):
                    current_start = _expand_start_with_banner(pname, pstart)
                    current_name = pname
                    pending_sig = None
                    balance += line.count("{") - line.count("}")
                    if balance == 0:
                        results.append(
                            {"name": current_name, "startLine": current_start, "endLine": line_no}
                        )
                        current_start = None
                        current_name = None
                    continue
                else:
                    # Linha não ignorable antes de abrir bloco => não é função
                    pending_sig = None

        # 3) Se estamos dentro de função, atualizar balance e fechar quando voltar a 0
        if current_start is not None and current_name is not None:
            if "{" in line or "}" in line:
                balance += line.count("{") - line.count("}")
                if balance == 0:
                    results.append(
                        {
                            "name": current_name,
                            "startLine": current_start,
                            "endLine": line_no,
                        }
                    )
                    current_start = None
                    current_name = None

    return results


# --- Identificador estável de função (nome+linhas) ---
def _stable_func_id(name: str, start_line: int, end_line: int) -> str:
    return f"{name}:{int(start_line)}-{int(end_line)}"


# --- Score de função por matches de indicadores e padrões (keylog, rede, etc.) ---
def _score_function_by_indicators(
    func_name: str,
    body_text: str,
    indicators: List[str],
) -> Dict[str, Any]:
    name = (func_name or "").strip()
    text = body_text or ""
    inds = [i for i in indicators if isinstance(i, str) and i.strip()]

    # Pesos por indicadores clássicos (Windows API) — mantemos simples e explicável.
    token_weights: Dict[str, int] = {
        # keylogging / input
        "GetAsyncKeyState": 35,
        "GetKeyState": 18,
        "SetWindowsHookEx": 40,
        "GetForegroundWindow": 10,
        # persistência (registo)
        "RegOpenKeyExA": 20,
        "RegOpenKeyExW": 20,
        "RegSetValueExA": 25,
        "RegSetValueExW": 25,
        "RegCreateKeyExA": 22,
        "RegCreateKeyExW": 22,
        # rede / C2
        "InternetOpenA": 18,
        "InternetOpenW": 18,
        "InternetOpenUrlA": 25,
        "InternetOpenUrlW": 25,
        "WinHttpOpen": 18,
        "WinHttpConnect": 22,
        "WinHttpSendRequest": 25,
        "URLDownloadToFile": 22,
        "WSAStartup": 10,
        "connect": 18,
        "send": 14,
        "recv": 14,
        # ficheiros
        "CreateFileA": 16,
        "CreateFileW": 16,
        "WriteFile": 18,
        "ReadFile": 10,
        "DeleteFileA": 14,
        "DeleteFileW": 14,
        # execução / injeção (pode variar conforme binário)
        "CreateProcessA": 20,
        "CreateProcessW": 20,
        "ShellExecuteA": 18,
        "ShellExecuteW": 18,
        "VirtualAlloc": 25,
        "WriteProcessMemory": 35,
        "CreateRemoteThread": 40,
    }

    # Padrões por strings comuns (ex.: chave Run, URL) — peso baixo/moderado.
    pattern_weights: List[Tuple[str, int, str]] = [
        (r"CurrentVersion\\Run", 28, "Persistência via chave Run (registo)"),
        (r"http://", 18, "Possível comunicação HTTP"),
        (r"https://", 18, "Possível comunicação HTTPS"),
    ]

    matched: List[str] = []
    reasons: List[str] = []
    score_raw = 0

    # 1) Nome suspeito (heurístico leve, só como bump)
    lowered = name.lower()
    if any(k in lowered for k in ("key", "keystroke", "hook", "persist", "exfil", "c2", "steal")):
        score_raw += 8
        reasons.append("Nome da função sugere comportamento suspeito")

    # 2) Matches exatos por tokens (preferir o que vem da análise estática)
    for tok in inds:
        w = token_weights.get(tok)
        if w:
            matched.append(tok)
            score_raw += w

    # 3) Padrões no corpo (regex simples)
    import re

    for pat, w, desc in pattern_weights:
        if re.search(pat, text, flags=re.IGNORECASE):
            score_raw += w
            reasons.append(desc)

    # 4) Sinais adicionais por presença no corpo mesmo sem vir na lista (fallback)
    for tok, w in token_weights.items():
        if tok in matched:
            continue
        if tok and tok in text:
            matched.append(tok)
            score_raw += max(6, int(w * 0.5))

    matched_unique: List[str] = []
    seen: Set[str] = set()
    for m in matched:
        if m not in seen:
            seen.add(m)
            matched_unique.append(m)

    # Normalização: o UI trata "score" como comparável (e.g. ordenação).
    # Para manter consistência com o score global (0-100), fazemos clamp para 0..100.
    score = int(min(max(score_raw, 0), 100))

    # Severidade (usa score normalizado 0-100)
    if score >= 75:
        severity = "CRÍTICO"
    elif score >= 45:
        severity = "ALTO"
    elif score >= 22:
        severity = "MÉDIO"
    else:
        severity = "BAIXO"

    if matched_unique:
        reasons.insert(0, "Indicadores: " + ", ".join(matched_unique[:10]) + ("…" if len(matched_unique) > 10 else ""))

    return {
        "score": int(score),
        "scoreRaw": int(score_raw),
        "severity": severity,
        "matchedIndicators": matched_unique,
        "reasons": reasons[:8],
    }


# --- Lista funções suspeitas com score a partir do pseudo-C e indicadores ---
def build_flagged_functions(
    c_source: str,
    analysis_results: Dict,
    flagged_indicators: List[str] | None = None,
) -> List[Dict[str, Any]]:
    functions = _parse_pseudo_c_functions(c_source)
    if not functions:
        return []

    static = analysis_results.get("static_analysis", {}) or {}
    suspicious_functions = [str(x) for x in static.get("suspicious_functions", []) or []]
    suspicious_imports = [str(x) for x in static.get("suspicious_imports", []) or []]
    all_indicators = [s for s in (flagged_indicators or []) if isinstance(s, str) and s.strip()]

    lines = c_source.split("\n")

# --- Extrai corpo e linhas de uma função ---
    def _function_body(func: Dict[str, Any]) -> Tuple[str, List[str]]:
        start = max(1, int(func.get("startLine", 1)))
        end = max(start, int(func.get("endLine", start)))
        snippet_lines = lines[start - 1 : end]
        return "\n".join(snippet_lines), snippet_lines

    flagged_funcs: List[Dict[str, Any]] = []

    for func in functions:
        name = str(func.get("name") or "")
        if not name:
            continue

        body_text, body_lines = _function_body(func)

        matched_indicators: List[str] = []

        # 1) Nome da função coincide (ou contém) alguma suspicious_function
        for sf in suspicious_functions:
            if not sf:
                continue
            if sf == name or sf in name or name in sf:
                matched_indicators.append(sf)

        # 2) Imports suspeitos presentes no corpo
        for imp in suspicious_imports:
            if not imp:
                continue
            if imp in body_text:
                matched_indicators.append(imp)

        # 3) Indicadores genéricos (YARA, C2, etc.) presentes no corpo
        for ind in all_indicators:
            if not ind:
                continue
            if ind in body_text:
                matched_indicators.append(ind)

        if not matched_indicators:
            continue

        # Remover duplicados mantendo ordem
        seen_ind: Set[str] = set()
        unique_inds: List[str] = []
        for s in matched_indicators:
            if s not in seen_ind:
                seen_ind.add(s)
                unique_inds.append(s)

        # Novo pipeline: score + razões
        scored = _score_function_by_indicators(name, body_text, unique_inds)

        flagged_funcs.append(
            {
                "name": name,
                "id": _stable_func_id(name, int(func.get("startLine", 1)), int(func.get("endLine", 1))),
                "startLine": int(func.get("startLine", 1)),
                "endLine": int(func.get("endLine", 1)),
                "indicators": unique_inds,
                "score": scored.get("score", 0),
                "severity": scored.get("severity", "BAIXO"),
                "reasons": scored.get("reasons", []),
            }
        )

    # Ordenar: mais grave primeiro, depois por score/linha
    sev_rank = {"CRÍTICO": 0, "ALTO": 1, "MÉDIO": 2, "BAIXO": 3}
    flagged_funcs.sort(
        key=lambda f: (
            sev_rank.get(str(f.get("severity") or "BAIXO").upper(), 9),
            -int(f.get("score") or 0),
            int(f.get("startLine") or 0),
        )
    )
    return flagged_funcs


# --- Re-alinha funções suspeitas ao pseudo-C truncado enviado ao frontend ---
def realign_flagged_functions_for_payload(
    c_code: str,
    flagged_functions: List[Dict[str, Any]] | None,
) -> List[Dict[str, Any]]:
    if not c_code or not flagged_functions:
        return []

    parsed = _parse_pseudo_c_functions(c_code)
    if not parsed:
        return []

    by_name: Dict[str, List[Dict[str, Any]]] = {}
    for fn in parsed:
        by_name.setdefault(str(fn.get("name") or ""), []).append(fn)

    total_lines = len(c_code.splitlines())
    realigned: List[Dict[str, Any]] = []

    for raw in flagged_functions:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or "")
        try:
            orig_start = int(raw.get("startLine", 0))
            orig_end = int(raw.get("endLine", 0))
        except (TypeError, ValueError):
            orig_start = orig_end = 0

        if orig_start > 0 and orig_end >= orig_start and orig_end <= total_lines:
            realigned.append(dict(raw))
            continue

        candidates = by_name.get(name, [])
        if not candidates and name:
            indicators = [s for s in (raw.get("indicators") or []) if isinstance(s, str) and s.strip()]
            body_lines = c_code.splitlines()
            for fn in parsed:
                start = int(fn.get("startLine", 0))
                end = int(fn.get("endLine", 0))
                if start <= 0 or end < start:
                    continue
                body = "\n".join(body_lines[start - 1 : end])
                if any(ind in body for ind in indicators):
                    candidates = [fn]
                    break

        if not candidates:
            continue

        best = min(candidates, key=lambda fn: abs(int(fn.get("startLine", 0)) - orig_start))
        updated = dict(raw)
        updated["startLine"] = int(best.get("startLine", 1))
        updated["endLine"] = int(best.get("endLine", updated["startLine"]))
        realigned.append(updated)

    return realigned
