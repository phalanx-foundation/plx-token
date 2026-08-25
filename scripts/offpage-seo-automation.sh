#!/usr/bin/env bash
# Run off-page SEO from PLX-ACTON root (loads .env, delegates to toolkit-staging).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/toolkit-staging/scripts/offpage-seo-automation.sh" "$@"
