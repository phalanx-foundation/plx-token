#!/usr/bin/env bash
# Phase 2 cron wrapper — process buyback-pending.json queue.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 scripts/buyback-swap-burn.py
