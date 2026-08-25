#!/usr/bin/env bash
# Non-interactive cNFT collection deploy — stdout is JSON only.
# Invoked by acton-worker POST /deploy-nft when NFT_TEMPLATE=cnft
#
# Merkle proofs matching on-chain cell.hash() need a dedicated builder;
# this path deploys with CNFT_MERKLE_ROOT (default 0) + CNFT_MAX_SUPPLY
# and persists NFT_ITEMS_JSON for a later SetMerkleRoot / claim pipeline.
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

COUNT_RAW="${NFT_ITEM_COUNT:-0}"
COUNT="$(python3 -c "s='${COUNT_RAW}'.replace(',',''); print(int(s) if s.isdigit() else 0)")"
export CNFT_MAX_SUPPLY="${CNFT_MAX_SUPPLY:-$(( COUNT > 0 ? COUNT : 256 ))}"
export CNFT_MERKLE_ROOT="${CNFT_MERKLE_ROOT:-0}"

ROYALTY_PERCENT="${ROYALTY_PERCENT:-0}"
export ROYALTY_FACTOR
ROYALTY_FACTOR="$(awk "BEGIN {printf \"%d\", ${ROYALTY_PERCENT} * 100}")"
export ROYALTY_BASE="${ROYALTY_BASE:-10000}"

if [[ -z "${NFT_DEPLOYER:-}" && -z "${JETTON_DEPLOYER:-}" ]]; then
  if [[ "$NETWORK" == "mainnet" ]]; then
    export JETTON_DEPLOYER="${JETTON_DEPLOYER_MAINNET:-toolkit-deployer-mainnet}"
  else
    export JETTON_DEPLOYER="${JETTON_DEPLOYER_TESTNET:-toolkit-deployer-testnet}"
  fi
fi

echo "[cnft-deploy] Building NftItem + CompressedNftCollection..." >&2
"$ACTON" build NftItem >&2
"$ACTON" build CompressedNftCollection >&2

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if ! "$ACTON" script scripts/deploy-cnft-collection.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton cnft deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
  exit 1
fi

COLLECTION="$(grep -oP 'TOOLKIT COLLECTION_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"
MERKLE_ROOT="$(grep -oP 'TOOLKIT MERKLE_ROOT=\K\S+' "$LOG" | tail -1 || true)"
MAX_SUPPLY="$(grep -oP 'TOOLKIT MAX_SUPPLY=\K\S+' "$LOG" | tail -1 || true)"

if [[ -z "$COLLECTION" ]]; then
  echo "{\"error\":\"missing collection_address in acton log\",\"log_tail\":\"$(tail -c 400 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
  exit 1
fi

if [[ -z "$TX" ]]; then
  TX="deploy-${COLLECTION}"
fi

mkdir -p "$ROOT/data"
PROOFS_FILE="$ROOT/data/cnft-proofs-${COLLECTION}.json"
python3 - <<PY
import json, os
payload = {
    "collection_address": "${COLLECTION}",
    "merkle_root": "${MERKLE_ROOT:-0}",
    "max_supply": int("${MAX_SUPPLY:-256}"),
    "items": json.loads(os.environ.get("NFT_ITEMS_JSON") or "[]"),
    "note": "On-chain merkle must use cell.hash() leaf layout; root 0 is placeholder until SetMerkleRoot.",
}
open(r"${PROOFS_FILE}", "w", encoding="utf-8").write(json.dumps(payload, indent=2))
print(json.dumps({
    "collection_address": "${COLLECTION}",
    "deploy_tx_hash": "${TX}",
    "merkle_root": "${MERKLE_ROOT:-0}",
    "max_supply": int("${MAX_SUPPLY:-256}"),
    "mode": "cnft_broadcast",
    "proofs_file": r"${PROOFS_FILE}",
}))
PY
