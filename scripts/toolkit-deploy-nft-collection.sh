#!/usr/bin/env bash
# Non-interactive NFT collection deploy — stdout is JSON only.
# Invoked by acton-worker POST /deploy-nft
#
# Required env: network (testnet|mainnet), NFT_OWNER_ADDRESS, COLLECTION_*
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-testnet}}"
export PATH="$(dirname "$ACTON"):$PATH"

OWNER="${NFT_OWNER_ADDRESS:-}"
if [[ -z "$OWNER" ]]; then
  echo '{"error":"NFT_OWNER_ADDRESS required"}' >&2
  exit 1
fi

# royalty percent -> factor (e.g. 5% -> 500 / 10000)
ROYALTY_PERCENT="${ROYALTY_PERCENT:-0}"
export ROYALTY_FACTOR
ROYALTY_FACTOR="$(awk "BEGIN {printf \"%d\", ${ROYALTY_PERCENT} * 100}")"
export ROYALTY_BASE="${ROYALTY_BASE:-10000}"

# Prefer NFT_DEPLOYER, else fall through to JETTON_DEPLOYER used by deploy-nft-collection.tolk
if [[ -z "${NFT_DEPLOYER:-}" && -z "${JETTON_DEPLOYER:-}" ]]; then
  if [[ "$NETWORK" == "mainnet" ]]; then
    export JETTON_DEPLOYER="${JETTON_DEPLOYER_MAINNET:-toolkit-deployer-mainnet}"
  else
    export JETTON_DEPLOYER="${JETTON_DEPLOYER_TESTNET:-toolkit-deployer-testnet}"
  fi
fi

echo "[nft-deploy] Building NftItem + NftCollection..." >&2
"$ACTON" build NftItem >&2
"$ACTON" build NftCollection >&2

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if ! "$ACTON" script scripts/deploy-nft-collection.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton nft deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
  exit 1
fi

COLLECTION="$(grep -oP 'TOOLKIT COLLECTION_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"

if [[ -z "$COLLECTION" ]]; then
  echo "{\"error\":\"missing collection_address in acton log\",\"log_tail\":\"$(tail -c 400 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
  exit 1
fi

if [[ -z "$TX" ]]; then
  TX="deploy-${COLLECTION}"
fi

# Item minting (NFT_ITEM_COUNT > 0) is a follow-up path; collection deploy is the gate.
python3 - <<PY
import json
print(json.dumps({
    "collection_address": "${COLLECTION}",
    "deploy_tx_hash": "${TX}",
    "item_addresses": [],
    "mode": "nft_broadcast",
}))
PY
