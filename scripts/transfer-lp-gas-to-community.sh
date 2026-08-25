#!/usr/bin/env bash
# Transfer Pioneer Season gas TON from plx-lp → plx-community (mainnet).
# Usage: bash scripts/transfer-lp-gas-to-community.sh
# Dry-run: DRY_RUN=1 bash scripts/transfer-lp-gas-to-community.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FROM_WALLET="${FROM_WALLET:-plx-lp}"
TO_WALLET="${TO_WALLET:-plx-community}"
TON_AMOUNT="${TON_AMOUNT:-3}"
TON_AMOUNT_NANO="${TON_AMOUNT_NANO:-$((TON_AMOUNT * 1000000000))}"
NET="${ACTON_NETWORK:-mainnet}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source <(grep -E '^(PLX_COMMUNITY|COMMUNITY_WALLET)' .env 2>/dev/null | sed 's/^/export /') || true
fi

resolve_addr() {
  local name="$1"
  acton script scripts/print-addrs.tolk --net "$NET" 2>/dev/null | awk -v w="$name" '$0 ~ w {print $NF; exit}'
}

TO_ADDRESS="${TO_ADDRESS:-${PLX_COMMUNITY_ADDRESS:-}}"
if [[ -z "$TO_ADDRESS" ]]; then
  TO_ADDRESS="$(resolve_addr "$TO_WALLET" || true)"
fi
if [[ -z "$TO_ADDRESS" ]]; then
  TO_ADDRESS="EQD1XDv0Awjx0GUVv6YQYYnvEmjcKJ9iEBjvtHPM2nWML-q9"
fi

echo "transfer-lp-gas-to-community: $FROM_WALLET -> $TO_ADDRESS amount ${TON_AMOUNT} TON (net=$NET)"

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "DRY_RUN=1 — no broadcast"
  exit 0
fi

export FROM_WALLET TO_ADDRESS TON_AMOUNT TON_AMOUNT_NANO
acton script scripts/send-ton.tolk --net "$NET"

echo "Done. Verify community balance on Tonviewer."
