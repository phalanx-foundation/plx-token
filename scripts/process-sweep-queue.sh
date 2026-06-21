#!/usr/bin/env bash
# Cron wrapper — process sweep-pending.json for deferred PayPal treasury sweeps.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi
python3 scripts/process-sweep-queue.py