#!/usr/bin/env bash
# Regenera requirements*.lock a partir dos ficheiros .txt editáveis (pip-tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
cd "$BACKEND"

ARGS=(--strip-extras --generate-hashes)

compile_one() {
  echo "pip-compile $1 -> $2"
  python -m piptools compile "$1" -o "$2" "${ARGS[@]}"
}

compile_one requirements.txt requirements.lock
compile_one requirements-dev.txt requirements-dev.lock
compile_one requirements-gui.txt requirements-gui.lock
compile_one requirements-ghidra.txt requirements-ghidra.lock

echo "[OK] Locks regenerados em backend/"
