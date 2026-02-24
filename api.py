"""
API REST para o RAT Analyzer.
Expõe um endpoint de upload e análise para o frontend (drop-n-analyze).
"""

import os
import sys
import uuid
import tempfile
from pathlib import Path
from typing import Iterable, List, Tuple

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

# Garantir que o projeto está no path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT_ROOT))

import config
from rat_analyzer import RATAnalyzer

app = FastAPI(title="RAT Analyzer API", version="1.0.0")

# CORS para o frontend React (Vite normalmente em localhost:8080 ou 5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://localhost:5173", "http://127.0.0.1:8080", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Limites de tamanho para o código C enviado ao frontend
MAX_CCODE_CHARS: int = 200_000  # ~200 KB de pseudo-C no payload
CCODE_WINDOW_RADIUS: int = 40   # ±40 linhas em volta de cada indicador


def _read_file_safe(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
    if not path or not Path(path).exists():
        return ""


def _normalize_indicators(flagged_indicators: Iterable[str]) -> List[str]:
    """Normaliza a lista de indicadores (trim, remove vazios/duplicados)."""
    seen = set()
    out: List[str] = []
    for raw in flagged_indicators or []:
        s = (raw or "").strip()
        if not s or s in seen:
            continue
        seen.add(s)
        out.append(s)
    return out


def _build_windows_around_indicators(lines: List[str], indicators: List[str], radius: int) -> List[Tuple[int, int]]:
    """
    Devolve intervalos de linhas [start, end] que cobrem janelas em volta de cada ocorrência
    de qualquer indicador. Usa índices 0-based.
    """
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

    if not ranges:
        return []

    # Fundir intervalos sobrepostos/adjacentes
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


def _summarize_c_code(c_code: str, flagged_indicators: Iterable[str], max_chars: int = MAX_CCODE_CHARS) -> str:
    """
    Se o pseudo-C for muito grande, devolve apenas janelas em volta das linhas que contêm
    indicadores suspeitos, com limite de tamanho total. Mantém o ficheiro original intacto
    no disco para download completo pelo utilizador.
    """
    if not c_code:
        return c_code
    if len(c_code) <= max_chars:
        return c_code

    indicators = _normalize_indicators(flagged_indicators)
    if not indicators:
        # Sem indicadores, limitar apenas por tamanho bruto (corta no fim com aviso)
        return c_code[:max_chars] + "\n/* ... saída truncada para evitar lag no frontend ... */"

    lines = c_code.split("\n")
    windows = _build_windows_around_indicators(lines, indicators, CCODE_WINDOW_RADIUS)
    if not windows:
        return c_code[:max_chars] + "\n/* ... saída truncada (nenhuma ocorrência explícita de indicadores no pseudo-C) ... */"

    out_lines: List[str] = []
    total_chars = 0
    placeholder = "/* ... código omitido para evitar lag no site ... */"

    for idx, (start, end) in enumerate(windows):
        # Separador entre blocos não contíguos
        if idx > 0:
            out_lines.append(placeholder)
        for i in range(start, end + 1):
            line = lines[i]
            out_lines.append(line)
            total_chars += len(line) + 1  # +1 pelo '\n'
            if total_chars >= max_chars:
                out_lines.append("/* ... saída truncada por tamanho total ... */")
                return "\n".join(out_lines)

    return "\n".join(out_lines)
    try:
        with open(path, encoding=encoding, errors=errors) as f:
            return f.read()
    except Exception:
        return ""


@app.post("/api/analyze")
async def analyze_file(file: UploadFile = File(...)):
    """
    Recebe um ficheiro (.exe, .dll, .cs), executa a análise e devolve
    relatório, código C#/C e assembly/IL para exibir no frontend.
    """
    # Validar extensão
    name = file.filename or "file"
    ext = Path(name).suffix.lower()
    if ext not in (".exe", ".dll", ".cs"):
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    suffix = ext
    prefix = "rat_"
    tmp_dir = Path(tempfile.mkdtemp(prefix=prefix))
    target_path = tmp_dir / name

    try:
        contents = await file.read()
        target_path.write_bytes(contents)
    except Exception as e:
        raise HTTPException(500, f"Erro ao guardar ficheiro: {e}")

    try:
        # Usar diretório de saída dedicado a este pedido
        output_dir = tmp_dir / "out"
        output_dir.mkdir(exist_ok=True)

        analyzer = RATAnalyzer(
            str(target_path),
            output_dir=str(output_dir),
            use_dotnet_decompiler=(ext in (".exe", ".dll")),
        )
        results = analyzer.analyze()
    except FileNotFoundError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        raise HTTPException(500, f"Erro na análise: {str(e)}")
    finally:
        # Limpeza: remover ficheiro temporário (opcional manter out_dir por um tempo)
        try:
            if target_path.exists():
                target_path.unlink()
        except Exception:
            pass

    # Ler last_analysis.json para obter caminhos do relatório e códigos
    last_path = output_dir / "last_analysis.json"
    report_content = ""
    c_code = ""
    il_code = ""

    flagged_indicators: list[str] = []
    if last_path.exists():
        import json
        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)
        report_path = last.get("report_path")
        report_content = _read_file_safe(report_path)
        flagged_indicators = last.get("flagged_indicators") or []

        # Código “C”: preferir C# descompilado (desobfuscado ou consolidado) ou pseudo-C
        deobf = last.get("deobfuscated_file")
        consolidated = last.get("consolidated_file")
        decompiled_c = last.get("decompiled_c_file")
        if deobf:
            c_code = _read_file_safe(deobf)
        if not c_code and consolidated:
            c_code = _read_file_safe(consolidated)
        if not c_code and decompiled_c:
            c_code = _read_file_safe(decompiled_c)
        if not c_code and last.get("decompilation_error_summary"):
            c_code = f"# Descompilação não disponível\n{last.get('decompilation_error_summary')}"

        # IL / Bytecode: assembly (desmontagem) ou mensagem
        disasm = last.get("disassembly_file")
        if disasm:
            il_code = _read_file_safe(disasm, errors="replace")
        if not il_code:
            il_code = "# Nenhum bytecode/assembly disponível para este ficheiro."
    else:
        report_content = "# Relatório não gerado."
        c_code = "# Código não disponível."
        il_code = "# Bytecode não disponível."

    return {
        "report": report_content,
        "cCode": c_code,
        "ilCode": il_code,
        "fileName": name,
        "riskScore": results.get("risk_score", 0),
        "riskLevel": results.get("risk_level", ""),
        "flaggedIndicators": flagged_indicators,
    }


@app.post("/api/analyze_stream")
async def analyze_file_stream(file: UploadFile = File(...)):
    """
    Versão com streaming: envia logs em tempo (quase) real + resultado final em NDJSON.
    Cada linha é um JSON com:
      - {"type": "log", "message": "..."}
      - {"type": "result", ...payload final...}
      - {"type": "error", "message": "..."} em caso de falha.
    """
    import json
    import queue
    import threading

    name = file.filename or "file"
    ext = Path(name).suffix.lower()
    if ext not in (".exe", ".dll", ".cs"):
        raise HTTPException(400, "Apenas ficheiros .exe, .dll ou .cs são suportados.")

    tmp_dir = Path(tempfile.mkdtemp(prefix="rat_stream_"))
    target_path = tmp_dir / name

    try:
        contents = await file.read()
        target_path.write_bytes(contents)
    except Exception as e:
        raise HTTPException(500, f"Erro ao guardar ficheiro: {e}")

    output_dir = tmp_dir / "out"
    output_dir.mkdir(exist_ok=True)

    q: "queue.Queue[object]" = queue.Queue()

    def log_cb(msg: str) -> None:
        q.put({"type": "log", "message": msg})

    def worker():
        try:
            analyzer = RATAnalyzer(
                str(target_path),
                output_dir=str(output_dir),
                use_dotnet_decompiler=(ext in (".exe", ".dll")),
                log_callback=log_cb,
            )
            results = analyzer.analyze()

            last_path = output_dir / "last_analysis.json"
            report_content = ""
            c_code = ""
            il_code = ""
            flagged_indicators: list[str] = []

            if last_path.exists():
                with open(last_path, encoding="utf-8") as f:
                    last = json.load(f)
                report_path = last.get("report_path")

                def _read_file_safe_local(path: str | None, encoding: str = "utf-8", errors: str = "replace") -> str:
                    if not path or not Path(path).exists():
                        return ""
                    try:
                        with open(path, encoding=encoding, errors=errors) as fh:
                            return fh.read()
                    except Exception:
                        return ""

                report_content = _read_file_safe_local(report_path)
                flagged_indicators = last.get("flagged_indicators") or []

                deobf = last.get("deobfuscated_file")
                consolidated = last.get("consolidated_file")
                decompiled_c = last.get("decompiled_c_file")
                if deobf:
                    c_code = _read_file_safe_local(deobf)
                if not c_code and consolidated:
                    c_code = _read_file_safe_local(consolidated)
                if not c_code and decompiled_c:
                    c_code = _read_file_safe_local(decompiled_c)
                if not c_code and last.get("decompilation_error_summary"):
                    c_code = f"# Descompilação não disponível\n{last.get('decompilation_error_summary')}"

                disasm = last.get("disassembly_file")
                if disasm:
                    il_code = _read_file_safe_local(disasm, errors="replace")
                if not il_code:
                    il_code = "# Nenhum bytecode/assembly disponível para este ficheiro."
            else:
                report_content = "# Relatório não gerado."
                c_code = "# Código não disponível."
                il_code = "# Bytecode não disponível."

            payload = {
                "type": "result",
                "report": report_content,
                "cCode": c_code,
                "ilCode": il_code,
                "fileName": name,
                "riskScore": results.get("risk_score", 0),
                "riskLevel": results.get("risk_level", ""),
                "flaggedIndicators": flagged_indicators,
            }
            q.put(payload)
        except FileNotFoundError as e:
            q.put({"type": "error", "message": str(e)})
        except Exception as e:
            q.put({"type": "error", "message": f"Erro na análise: {e}"})
        finally:
            q.put(None)
            try:
                if target_path.exists():
                    target_path.unlink()
            except Exception:
                pass

    threading.Thread(target=worker, daemon=True).start()

    async def streamer():
        import anyio

        while True:
            item = await anyio.to_thread.run_sync(q.get)
            if item is None:
                break
            try:
                line = json.dumps(item, ensure_ascii=False) + "\n"
            except Exception:
                continue
            yield line.encode("utf-8")

    return StreamingResponse(streamer(), media_type="application/x-ndjson")


@app.get("/api/health")
async def health():
    return {"status": "ok"}
