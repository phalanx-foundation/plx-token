#!/usr/bin/env bash
# Pioneer Season PLX batch wrapper.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 scripts/airdrop-season-batch.py "$@"
