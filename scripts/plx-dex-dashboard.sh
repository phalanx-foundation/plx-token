#!/usr/bin/env bash
# PLX market dashboard — wrapper (loads .env if present)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
exec python3 "$ROOT/scripts/plx-dex-dashboard.py" "$@"
