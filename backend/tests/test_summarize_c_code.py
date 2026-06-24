# --- Módulo: test_summarize_c_code ---
# Testes da truncagem de pseudo-C no payload (summarize_c_code).

from analysis_jobs import summarize_c_code, summarize_c_code_payload
from modules.pseudo_c_highlighter import realign_flagged_functions_for_payload


# --- Teste: verifica codigo curto devolvido integral ---
def test_codigo_curto_devolvido_integral():
    code = "int main() { return 0; }"
    assert summarize_c_code(code, [], max_chars=1000) == code


# --- Teste: verifica truncagem simples sem indicadores ---
def test_truncagem_simples_sem_indicadores():
    code = "\n".join(f"linha_{i};" for i in range(2000))
    out = summarize_c_code(code, [], max_chars=2000)
    assert len(out) <= 2200  # margem para header/rodapé
    assert "[RESUMO]" in out
    assert "truncado" in out


# --- Teste: verifica truncagem mantem janela do indicador ---
def test_truncagem_mantem_janela_do_indicador():
    lines = [f"linha_{i};" for i in range(2000)]
    lines[1500] = "CreateRemoteThread(processo);"
    code = "\n".join(lines)
    out = summarize_c_code(code, ["CreateRemoteThread"], max_chars=20000)
    assert len(out) < len(code)
    assert "CreateRemoteThread" in out


# --- Teste: verifica payload realinha flagged functions ---
def test_payload_realinha_flagged_functions():
    lines = [f"linha_{i};" for i in range(4000)]
    lines[1500] = "void FUN_suspeita(void) {"
    lines[1501] = "  CreateRemoteThread(proc);"
    lines[1502] = "}"
    code = "\n".join(lines)
    flagged = [
        {
            "name": "FUN_suspeita",
            "startLine": 1501,
            "endLine": 1503,
            "indicators": ["CreateRemoteThread"],
            "severity": "ALTO",
            "score": 80,
        }
    ]
    summarized, aligned = summarize_c_code_payload(
        code, ["CreateRemoteThread"], flagged, max_chars=20000
    )
    assert "CreateRemoteThread" in summarized
    assert len(aligned) == 1
    assert 1 <= aligned[0]["startLine"] <= aligned[0]["endLine"]
    assert aligned[0]["endLine"] <= len(summarized.splitlines())


# --- Teste: verifica realign flagged functions for payload por nome ---
def test_realign_flagged_functions_for_payload_por_nome():
    summarized = "\n".join(
        [
            "// [RESUMO] truncado",
            "// ... linhas 1501-1503 ...",
            "void FUN_suspeita(void)",
            "{",
            "  CreateRemoteThread(proc);",
            "}",
        ]
    )
    flagged = [
        {
            "name": "FUN_suspeita",
            "startLine": 1501,
            "endLine": 1503,
            "indicators": ["CreateRemoteThread"],
        }
    ]
    aligned = realign_flagged_functions_for_payload(summarized, flagged)
    assert len(aligned) == 1
    assert aligned[0]["startLine"] >= 1
    assert aligned[0]["endLine"] <= len(summarized.splitlines())
