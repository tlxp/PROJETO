#!/usr/bin/env python3
# --- Módulo: check_job_snippets ---
# Consulta a API para um job e mostra se existem ficheiros de trechos obfuscados.
# Uso: python scripts/check_job_snippets.py <job_id> [--base-url http://localhost:8000]

import argparse
import json
import sys
from pathlib import Path

# *backend no path*
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import urllib.request


# --- Ponto de entrada CLI ---
def main():
    parser = argparse.ArgumentParser(description="Verifica payload do job (trechos obfuscados)")
    parser.add_argument("job_id", help="ID do job (ex.: 44daf45e-503c-4049-9d16-51064837da99)")
    parser.add_argument("--base-url", default="http://localhost:8000", help="URL base da API")
    args = parser.parse_args()
    url = f"{args.base_url.rstrip('/')}/api/analysis/{args.job_id}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        print(f"Erro ao chamar API: {e}")
        return 1
    sr = data.get("staticResult") or {}
    if isinstance(sr, str):
        try:
            sr = json.loads(sr)
        except Exception:
            sr = {}
    obf = sr.get("obfuscatedSnippetsFile") or ""
    deob = sr.get("obfuscatedSnippetsDeobfuscatedFile") or ""
    print(f"Job: {data.get('id')}")
    print(f"Status: {data.get('status')}")
    print(f"obfuscatedSnippetsFile: {repr(obf)}")
    print(f"obfuscatedSnippetsDeobfuscatedFile: {repr(deob)}")
    has_any = bool(obf or deob)
    print(f"\nBotões 'Ver trechos' devem aparecer: {'Sim' if has_any else 'Não'}")
    if not has_any:
        print("(O relatório pode mencionar ofuscação na secção DEOBFUSCAÇÃO, mas não há ficheiros de trechos extraídos para este job.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
