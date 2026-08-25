#!/usr/bin/env bash
# Non-interactive NFT collection deploy — stdout is JSON only.
# Invoked by acton-worker POST /deploy-nft
#
# Required env: network (testnet|mainnet), NFT_OWNER_ADDRESS, COLLECTION_*
# Optional: NFT_ITEM_COUNT, NFT_ITEMS_JSON (array of {name,description,imageUrl})
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
# Keep deploy timeout safe (acton-worker default 300s)
if (( COUNT > 20 )); then
  echo "{\"error\":\"NFT_ITEM_COUNT too large for single deploy (${COUNT}); max 20\"}" >&2
  exit 1
fi
export NFT_ITEM_COUNT="$COUNT"

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
ESCROW="$(grep -oP 'TOOLKIT COLLECTION_ESCROW=\K\S+' "$LOG" | tail -1 || true)"

if [[ -z "$COLLECTION" ]]; then
  echo "{\"error\":\"missing collection_address in acton log\",\"log_tail\":\"$(tail -c 400 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
  exit 1
fi

if [[ -z "$TX" ]]; then
  TX="deploy-${COLLECTION}"
fi

export NFT_COLLECTION_ADDRESS="$COLLECTION"
export NFT_OWNER_ADDRESS="$OWNER"

ITEM_ADDRS=()
if (( COUNT > 0 )); then
  echo "[nft-deploy] Minting ${COUNT} items (escrow=${ESCROW})..." >&2
  for ((i=0; i<COUNT; i++)); do
    ITEM_META="$(NFT_ITEMS_JSON="${NFT_ITEMS_JSON:-[]}" python3 -c "
import json, os
items = json.loads(os.environ.get('NFT_ITEMS_JSON') or '[]')
i = ${i}
if isinstance(items, list) and i < len(items) and isinstance(items[i], dict):
    d = items[i]
    print(json.dumps({
        'name': str(d.get('name') or f'Item {i}'),
        'description': str(d.get('description') or ''),
        'imageUrl': str(d.get('imageUrl') or d.get('image') or ''),
    }))
else:
    print(json.dumps({'name': f'Item {i}', 'description': '', 'imageUrl': ''}))
")"
    export NFT_ITEM_INDEX="$i"
    export NFT_ITEM_OWNER="$OWNER"
    export NFT_ITEM_NAME="$(echo "$ITEM_META" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")"
    export NFT_ITEM_DESCRIPTION="$(echo "$ITEM_META" | python3 -c "import sys,json; print(json.load(sys.stdin)['description'])")"
    export NFT_ITEM_IMAGE_URL="$(echo "$ITEM_META" | python3 -c "import sys,json; print(json.load(sys.stdin)['imageUrl'])")"

    MINT_LOG="$(mktemp)"
    if ! "$ACTON" script scripts/mint-nft-item.tolk --net "$NETWORK" >"$MINT_LOG" 2>&1; then
      echo "{\"error\":\"mint item ${i} failed\",\"log_tail\":\"$(tail -c 400 "$MINT_LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
      rm -f "$MINT_LOG"
      exit 1
    fi
    ITEM_ADDR="$(grep -oP 'TOOLKIT NFT_ITEM_ADDRESS=\K\S+' "$MINT_LOG" | tail -1 || true)"
    rm -f "$MINT_LOG"
    if [[ -n "$ITEM_ADDR" ]]; then
      ITEM_ADDRS+=("$ITEM_ADDR")
    fi
  done

  echo "[nft-deploy] Transferring collection ownership to client..." >&2
  OWN_LOG="$(mktemp)"
  export NFT_NEW_OWNER_ADDRESS="$OWNER"
  if ! "$ACTON" script scripts/nft-change-collection-owner.tolk --net "$NETWORK" >"$OWN_LOG" 2>&1; then
    echo "{\"error\":\"change collection owner failed\",\"log_tail\":\"$(tail -c 400 "$OWN_LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
    rm -f "$OWN_LOG"
    exit 1
  fi
  rm -f "$OWN_LOG"
fi

ITEM_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "${ITEM_ADDRS[@]+"${ITEM_ADDRS[@]}"}")"
python3 - <<PY
import json
print(json.dumps({
    "collection_address": "${COLLECTION}",
    "deploy_tx_hash": "${TX}",
    "item_addresses": json.loads('''${ITEM_JSON}'''),
    "mode": "nft_broadcast",
}))
PY
