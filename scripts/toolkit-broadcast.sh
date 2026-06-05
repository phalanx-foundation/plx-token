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

if ! "$ACTON" script scripts/deploy-client-jetton.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

MINTER="$(grep -oP 'TOOLKIT MINTER_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"
PENDING="$(grep -oP 'TOOLKIT PENDING_ADMIN_CLAIM=\K\S+' "$LOG" | tail -1 || true)"

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

python3 - <<PY
import json
print(json.dumps({
    "minter_address": "${MINTER}",
    "deploy_tx_hash": "${TX}",
    "pending_admin_claim": "${PENDING}" == "true",
}))
PY
