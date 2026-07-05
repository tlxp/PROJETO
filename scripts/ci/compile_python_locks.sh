# --- Módulo: compile_python_locks.sh ---
# --- Regenera requirements*.lock via pip-tools (hashes reprodutíveis) ---
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
cd "$BACKEND"

ARGS=(--strip-extras --generate-hashes)

POSTPROCESS="$(cd "$(dirname "$0")" && pwd)/postprocess_lock.py"

# --- Invoca pip-compile para um par source/output ---
compile_one() {
  echo "pip-compile $1 -> $2"
  local tmp
  tmp="$(mktemp)"
  python -m piptools compile "$1" -o "$tmp" "${ARGS[@]}"
  python "$POSTPROCESS" "$tmp" "$2"
  rm -f "$tmp"
}

# --- Compilação de todos os ficheiros lock do backend ---
compile_one requirements.txt requirements.lock
compile_one requirements-dev.txt requirements-dev.lock
compile_one requirements-gui.txt requirements-gui.lock
compile_one requirements-ghidra.txt requirements-ghidra.lock

echo "[OK] Locks regenerados em backend/"
