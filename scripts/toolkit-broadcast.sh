#!/usr/bin/env bash
# Non-interactive toolkit client jetton deploy — stdout is JSON only.
# Invoked by acton-worker on Ubuntu or via ACTON_DEPLOY_CMD locally.
#
# Required env: network (testnet|mainnet), JETTON_* (see deploy-client-jetton.tolk)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-testnet}}"

export JETTON_IMAGE="${JETTON_IMAGE:-${JETTON_IMAGE_URL:-}}"

SUPPLY_RAW="${JETTON_SUPPLY:-0}"
SUPPLY_CLEAN="${SUPPLY_RAW//,/}"
DECIMALS="${JETTON_DECIMALS:-9}"
export JETTON_MINT_AMOUNT_NANO="$(
  python3 -c "s='${SUPPLY_CLEAN}'; d=int('${DECIMALS}'); print(int(s)*10**d if s.isdigit() else 0)"
)"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Multi-wallet distribution (Distribution/Enterprise tiers) uses a dedicated
# script that mints per-bucket + deploys vesting; else standard single mint.
ALLOC_COUNT="${JETTON_ALLOC_COUNT:-0}"
if [[ "$ALLOC_COUNT" =~ ^[0-9]+$ && "$ALLOC_COUNT" -gt 0 ]]; then
  DEPLOY_SCRIPT="scripts/deploy-distribution-client.tolk"
else
  DEPLOY_SCRIPT="scripts/deploy-client-jetton.tolk"
fi

if ! "$ACTON" script "$DEPLOY_SCRIPT" --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

MINTER="$(grep -oP 'TOOLKIT MINTER_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"
PENDING="$(grep -oP 'TOOLKIT PENDING_ADMIN_CLAIM=\K\S+' "$LOG" | tail -1 || true)"
# Collect deployed vesting contract addresses (distribution buckets with lock).
VESTING_ADDRS="$(grep -oP 'TOOLKIT ALLOC_VESTING=\K\S+' "$LOG" || true)"

if [[ -z "$MINTER" ]]; then
  MINTER="$(grep -oP 'JETTON MINTER_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
fi

if [[ -z "$MINTER" ]]; then
  echo "{\"error\":\"missing minter_address in acton log\"}" >&2
  exit 1
fi

if [[ -z "$TX" ]]; then
  TX="deploy-${MINTER}"
fi

VESTING_ADDRS="${VESTING_ADDRS}" python3 - <<PY
import json, os
vesting = [a for a in os.environ.get("VESTING_ADDRS", "").split() if a.strip()]
print(json.dumps({
    "minter_address": "${MINTER}",
    "deploy_tx_hash": "${TX}",
    "pending_admin_claim": "${PENDING}" == "true",
    "vesting_contracts": vesting,
}))
PY
