# --- Módulo: obfuscation_snippet_extractor ---
# Extrai trechos obfuscados do código fonte e grava ficheiros separados (original/deobfuscado).

import binascii
import logging
import re
import base64
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List

_LOGGER = logging.getLogger(__name__)

try:
    import config as _config
    MAX_SNIPPETS = getattr(_config, "OBFUSCATION_SNIPPETS_MAX", 50)
    CONTEXT_LINES = getattr(_config, "OBFUSCATION_CONTEXT_LINES", 3)
    MAX_SNIPPET_LINES = getattr(_config, "OBFUSCATION_SNIPPET_MAX_LINES", 50)
except ImportError:
    MAX_SNIPPETS = 50
    CONTEXT_LINES = 3
    MAX_SNIPPET_LINES = 50


@dataclass
# --- Trecho de código com obfuscação detetada (posição e tipo) ---
class ObfuscationSnippet:
    type: str
    description: str
    line_start: int
    line_end: int
    snippet: str
    source_file: str


# Padrões de ofuscação (alinhados com Deobfuscator._detect_obfuscation e Base64 em fonte)
OBFUSCATION_PATTERNS: List[tuple] = [
    (r'[a-zA-Z]{1,2}\s*=\s*[a-zA-Z]{1,2}\s*\+\s*[a-zA-Z]{1,2}', "String concatenation obfuscation"),
    (r'"\s*\+\s*"[^"]*"', "C# string concatenation"),
    (r'GetFolderPath\s*\([^)]+\)\s*\+', "Path building with GetFolderPath"),
    (r'Path\.Combine\s*\(', "Path.Combine (pode indicar paths sensíveis)"),
    (r'chr\(0x[0-9a-fA-F]+\)', "Character encoding"),
    (r'eval\(', "Eval usage"),
    (r'exec\(', "Exec usage"),
    (r'__import__', "Dynamic import"),
    (r'getattr\(', "Dynamic attribute access"),
    (r'Convert\.FromBase64String', "Base64 decode em código"),
    (r'Encoding\.UTF8\.GetString', "Decoding de bytes para string"),
    (r'"([A-Za-z0-9+/]{20,}={0,2})"', "Base64 literal in source"),
]

# Falsos positivos para Base64 (nomes .NET comuns)
BASE64_FALSE_POSITIVES = (
    'attribute', 'assembly', 'compiler', 'runtime', 'configuration',
    'version', 'framework', 'compatibility', 'generated', 'compilation',
    'refsafety', 'rules', 'requested', 'execution', 'privileges',
    'product', 'company', 'title', 'target', 'informational', 'file',
)


# --- Heurística conservadora para reduzir falsos positivos de Base64 ---
def _is_probable_base64_literal(s: str) -> bool:
    if not s or not isinstance(s, str):
        return False
    s = s.strip()
    if len(s) < 20 or len(s) > 4096:
        return False
    if not re.fullmatch(r"[A-Za-z0-9+/=]+", s):
        return False
    # Exigir diversidade mínima de classes para evitar strings "normais" com slash.
    classes = 0
    if any(c.islower() for c in s):
        classes += 1
    if any(c.isupper() for c in s):
        classes += 1
    if any(c.isdigit() for c in s):
        classes += 1
    if "+" in s or "/" in s:
        classes += 1
    if "=" in s:
        classes += 1
    if classes < 3:
        return False
    low = s.lower()
    if any(fp in low for fp in BASE64_FALSE_POSITIVES):
        return False
    return True


# --- Decodifica Base64 apenas quando resultar em texto UTF-8 legível ---
def _decode_base64_text_if_readable(s: str) -> str | None:
    if not _is_probable_base64_literal(s):
        return None
    try:
        padded = s + ("=" * ((4 - (len(s) % 4)) % 4))
        raw = base64.b64decode(padded, validate=True)
    except (binascii.Error, ValueError):
        return None
    if len(raw) < 4:
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    printable = sum(1 for c in text if c.isprintable() or c in "\n\r\t")
    if len(text) == 0 or printable / len(text) < 0.85:
        return None
    if not any(c.isalpha() for c in text):
        return None
    return text


# --- Número de linha (1-based) do offset no texto ---
def _line_at_offset(content: str, offset: int) -> int:
    if offset <= 0:
        return 1
    return content[:offset].count("\n") + 1


# --- Extrai bloco de linhas [line_start, line_end] com limite de tamanho ---
def _extract_snippet_lines(lines: List[str], line_start: int, line_end: int) -> str:
    start = max(0, line_start - 1)
    end = min(len(lines), line_end)
    window = lines[start:end]
    if len(window) > MAX_SNIPPET_LINES:
        window = window[:MAX_SNIPPET_LINES]
        # Ajustar line_end para refletir o truncamento
        end = start + len(window)
    return "\n".join(window)


# --- Deteta obfuscação com posição e extrai trechos com janela de contexto ---
def detect_obfuscation_with_positions(
    source_content: str,
    source_path: str = "",
) -> List[ObfuscationSnippet]:
    snippets: List[ObfuscationSnippet] = []
    lines = source_content.split("\n")
    seen: set = set()  # (line_center, type) para evitar duplicados

    for pattern, description in OBFUSCATION_PATTERNS:
        if len(snippets) >= MAX_SNIPPETS:
            break
        try:
            regex = re.compile(pattern, re.IGNORECASE)
        except re.error:
            continue
        for m in regex.finditer(source_content):
            if len(snippets) >= MAX_SNIPPETS:
                break
            start_line = _line_at_offset(source_content, m.start())
            end_line = _line_at_offset(source_content, m.end())
            # Janela de contexto
            line_center = (start_line + end_line) // 2
            win_start = max(1, line_center - CONTEXT_LINES)
            win_end = min(len(lines), line_center + CONTEXT_LINES)
            key = (line_center, description)
            if key in seen:
                continue
            seen.add(key)
            # Filtrar Base64: evitar falsos positivos
            if "Base64 literal" in description:
                b64_match = m.group(1) if m.lastindex and m.lastindex >= 1 else ""
                decoded_preview = _decode_base64_text_if_readable(b64_match)
                if not decoded_preview:
                    continue
            snippet_text = _extract_snippet_lines(lines, win_start, win_end)
            snippets.append(ObfuscationSnippet(
                type="obfuscation",
                description=description,
                line_start=win_start,
                line_end=win_end,
                snippet=snippet_text,
                source_file=source_path,
            ))
    return snippets


# --- Escreve ficheiro de trechos obfuscados (original) com secções delimitadas ---
def write_obfuscated_snippets_file(snippets: List[ObfuscationSnippet], output_path: Path) -> None:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sections = []
    for i, s in enumerate(snippets, 1):
        sections.append(f"--- snippet {i} ---")
        sections.append(f"type: {s.type}")
        sections.append(f"description: {s.description}")
        sections.append(f"line: {s.line_start}-{s.line_end}")
        sections.append(f"source_file: {s.source_file}")
        sections.append("")
        sections.append(s.snippet)
        sections.append("")
    try:
        output_path.write_text("\n".join(sections), encoding="utf-8", errors="replace")
        _LOGGER.info("Trechos obfuscados guardados: %s (%d snippets)", output_path, len(snippets))
    except OSError as e:
        _LOGGER.exception("Erro ao escrever ficheiro de trechos obfuscados %s: %s", output_path, e)
        raise


# --- Escreve ficheiro de trechos deobfuscados (aplica deobfuscate_fn por snippet) ---
def write_deobfuscated_snippets_file(
    snippets: List[ObfuscationSnippet],
    output_path: Path,
    deobfuscate_fn: Callable[[str], str],
) -> None:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sections = []
    for i, s in enumerate(snippets, 1):
        deob_snippet = deobfuscate_fn(s.snippet)
        sections.append(f"--- snippet {i} ---")
        sections.append(f"type: {s.type}")
        sections.append(f"description: {s.description}")
        sections.append(f"line: {s.line_start}-{s.line_end}")
        sections.append(f"source_file: {s.source_file}")
        sections.append("")
        sections.append(deob_snippet)
        sections.append("")
    try:
        output_path.write_text("\n".join(sections), encoding="utf-8", errors="replace")
        _LOGGER.info("Trechos deobfuscados guardados: %s (%d snippets)", output_path, len(snippets))
    except OSError as e:
        _LOGGER.exception("Erro ao escrever ficheiro de trechos deobfuscados %s: %s", output_path, e)
        raise


# --- Dicionário descrição → contagem para relatório ---
def build_snippets_summary(snippets: List[ObfuscationSnippet]) -> Dict[str, int]:
    return dict(Counter(s.description for s in snippets))


# --- Deteta, grava ficheiros e devolve caminhos (conteúdo em memória) ---
def extract_and_write_snippets_from_content(
    content: str,
    source_path: str,
    output_dir: Path,
    stem: str,
    deobfuscate_fn: Callable[[str], str],
) -> tuple:
    snippets = detect_obfuscation_with_positions(content, source_path=source_path)
    if not snippets:
        return ("", "", {})
    obf_path = output_dir / f"{stem}.obfuscated_snippets.txt"
    deob_path = output_dir / f"{stem}.obfuscated_snippets_deobfuscated.txt"
    write_obfuscated_snippets_file(snippets, obf_path)
    write_deobfuscated_snippets_file(snippets, deob_path, deobfuscate_fn)
    return (str(obf_path), str(deob_path), build_snippets_summary(snippets))


# --- Lê ficheiro consolidado, deteta trechos e grava ficheiros obfuscado/deobfuscado ---
def extract_and_write_snippets(
    consolidated_path: str,
    output_dir: Path,
    stem: str,
    deobfuscate_fn: Callable[[str], str],
) -> tuple:
    path = Path(consolidated_path)
    if not path.exists():
        return ("", "", {})
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        _LOGGER.warning("Não foi possível ler ficheiro consolidado %s: %s", consolidated_path, e)
        return ("", "", {})
    snippets = detect_obfuscation_with_positions(content, source_path=consolidated_path)
    if not snippets:
        return ("", "", {})
    obf_path = output_dir / f"{stem}.obfuscated_snippets.txt"
    deob_path = output_dir / f"{stem}.obfuscated_snippets_deobfuscated.txt"
    write_obfuscated_snippets_file(snippets, obf_path)
    write_deobfuscated_snippets_file(snippets, deob_path, deobfuscate_fn)
    return (str(obf_path), str(deob_path), build_snippets_summary(snippets))
