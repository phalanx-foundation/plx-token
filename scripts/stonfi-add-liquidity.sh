#!/usr/bin/env bash
# Phase 3 — Ston.fi LP automation wrapper (requires LP_TON_NANO env).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 scripts/stonfi-add-liquidity.py
