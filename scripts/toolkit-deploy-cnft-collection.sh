#!/usr/bin/env bash
# Non-interactive cNFT collection deploy — stdout is JSON only.
# Invoked by acton-worker POST /deploy-nft when NFT_TEMPLATE=cnft
#
# Builds TVM-compatible merkle (scripts/cnft_merkle.py) then deploys with root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-testnet}}"
export PATH="$(dirname "$ACTON"):$PATH"
# Prefer Acton worker venv (has pytoniq-core on Ubuntu)
if [[ -z "${PYTHON:-}" ]]; then
  if [[ -x "$HOME/projects/plx-acton/toolkit-staging/acton-worker/.venv/bin/python" ]]; then
    PYTHON="$HOME/projects/plx-acton/toolkit-staging/acton-worker/.venv/bin/python"
  else
    PYTHON="python3"
  fi
fi

OWNER="${NFT_OWNER_ADDRESS:-}"
if [[ -z "$OWNER" ]]; then
  echo '{"error":"NFT_OWNER_ADDRESS required"}' >&2
  exit 1
fi

COUNT_RAW="${NFT_ITEM_COUNT:-0}"
COUNT="$("$PYTHON" -c "s='${COUNT_RAW}'.replace(',',''); print(int(s) if s.isdigit() else 0)")"
if (( COUNT > 256 )); then
  echo "{\"error\":\"NFT_ITEM_COUNT too large (${COUNT}); max 256\"}" >&2
  exit 1
fi

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

# Ensure leaves have owners (default: collection owner)
ITEMS_JSON="${NFT_ITEMS_JSON:-[]}"

# Guard: never silently commit an all-zero (unclaimable) merkle root.
# That only happens when there are no real items: count 0/unset AND no items.
# An empty/whitespace NFT_ITEMS_JSON or an explicit "[]" counts as "no items".
ITEMS_JSON_RAW="${NFT_ITEMS_JSON:-}"
ITEMS_JSON_TRIMMED="$(printf '%s' "$ITEMS_JSON_RAW" | tr -d '[:space:]')"
if (( COUNT == 0 )) && { [[ -z "$ITEMS_JSON_TRIMMED" ]] || [[ "$ITEMS_JSON_TRIMMED" == "[]" ]]; }; then
  echo '{"error":"empty deploy blocked: supply NFT_ITEMS_JSON with real items and a nonzero NFT_ITEM_COUNT (an all-zero merkle root would be unclaimable)"}' >&2
  exit 1
fi

MERKLE_TMP="$(mktemp)"
LOG=""
cleanup() { rm -f "$MERKLE_TMP"; [[ -n "${LOG}" ]] && rm -f "$LOG"; }
trap cleanup EXIT

if ! "$PYTHON" scripts/cnft_merkle.py \
    --owner "$OWNER" \
    --count "$COUNT" \
    --items-json "$ITEMS_JSON" \
    --out "$MERKLE_TMP" >/dev/null; then
  echo '{"error":"cnft_merkle.py failed (need pytoniq-core)"}' >&2
  exit 1
fi

export CNFT_MERKLE_ROOT
CNFT_MERKLE_ROOT="$("$PYTHON" -c "import json; print(json.load(open(r'$MERKLE_TMP'))['merkle_root'])")"
export CNFT_MAX_SUPPLY
CNFT_MAX_SUPPLY="$("$PYTHON" -c "import json; print(json.load(open(r'$MERKLE_TMP'))['max_supply'])")"

echo "[cnft-deploy] merkle_root=${CNFT_MERKLE_ROOT} max_supply=${CNFT_MAX_SUPPLY} items=${COUNT}" >&2

echo "[cnft-deploy] Building NftItem + CompressedNftCollection..." >&2
"$ACTON" build NftItem >&2
"$ACTON" build CompressedNftCollection >&2

LOG="$(mktemp)"

if ! "$ACTON" script scripts/deploy-cnft-collection.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton cnft deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\' | tr '\n' ' ')\"}" >&2
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

mkdir -p "$ROOT/data"
PROOFS_FILE="$ROOT/data/cnft-proofs-${COLLECTION}.json"
export NFT_ITEMS_JSON="$ITEMS_JSON"
"$PYTHON" - <<PY
import json, os
merkle = json.load(open(r"${MERKLE_TMP}", encoding="utf-8"))
merkle["collection_address"] = "${COLLECTION}"
merkle["deploy_tx_hash"] = "${TX}"
try:
    merkle["items"] = json.loads(os.environ.get("NFT_ITEMS_JSON") or "[]")
except json.JSONDecodeError:
    merkle["items"] = []
open(r"${PROOFS_FILE}", "w", encoding="utf-8").write(json.dumps(merkle, indent=2))
print(json.dumps({
    "collection_address": "${COLLECTION}",
    "deploy_tx_hash": "${TX}",
    "merkle_root": merkle["merkle_root"],
    "merkle_root_hex": merkle.get("merkle_root_hex"),
    "max_supply": merkle["max_supply"],
    "item_count": merkle.get("item_count", 0),
    "mode": "cnft_broadcast",
    "proofs_file": r"${PROOFS_FILE}",
    "hash_scheme": merkle.get("hash_scheme"),
}))
PY
