#!/usr/bin/env bash
# Transfer TON from plx-scratch-seeker-payment → toolkit-deployer-mainnet (deploy gas).
# Usage:
#   TON_AMOUNT=5 bash scripts/transfer-scratch-gas-to-deployer.sh
#   DRY_RUN=1 TON_AMOUNT=5 bash scripts/transfer-scratch-gas-to-deployer.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then set -a; source .env; set +a; fi

FROM_WALLET="${FROM_WALLET:-plx-scratch-seeker-payment}"
TO_WALLET="${TO_WALLET:-toolkit-deployer-mainnet}"
TON_AMOUNT="${TON_AMOUNT:-}"
TON_AMOUNT_NANO="${TON_AMOUNT_NANO:-}"
NET="${ACTON_NETWORK:-mainnet}"
ACTON="${ACTON:-$HOME/.acton/bin/acton}"

if [[ -z "$TON_AMOUNT" && -z "$TON_AMOUNT_NANO" ]]; then
  echo "Set TON_AMOUNT (whole/fraction TON) or TON_AMOUNT_NANO" >&2
  exit 1
fi
if [[ -z "$TON_AMOUNT_NANO" ]]; then
  TON_AMOUNT_NANO="$(python3 -c "print(int(float('${TON_AMOUNT}') * 1_000_000_000))")"
fi

TO_ADDRESS="${TO_ADDRESS:-${JETTON_DEPLOYER_ADDRESS_MAINNET:-}}"
if [[ -z "$TO_ADDRESS" ]]; then
  TO_ADDRESS="$("$ACTON" script scripts/print-addrs.tolk --net "$NET" 2>/dev/null | awk -v w="$TO_WALLET" '$0 ~ w {print $NF; exit}')"
fi
if [[ -z "$TO_ADDRESS" ]]; then
  echo "TO_ADDRESS / JETTON_DEPLOYER_ADDRESS_MAINNET not resolved" >&2
  exit 1
fi

echo "transfer-scratch-gas-to-deployer: $FROM_WALLET -> $TO_ADDRESS amount_nano=$TON_AMOUNT_NANO (net=$NET)"

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "DRY_RUN=1 — no broadcast"
  exit 0
fi

export FROM_WALLET TO_ADDRESS TON_AMOUNT_NANO
"$ACTON" script scripts/send-ton.tolk --net "$NET"
echo "Done. Verify deploy gas wallet on Tonviewer."
