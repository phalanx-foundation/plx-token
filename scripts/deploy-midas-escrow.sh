#!/usr/bin/env bash
# Non-interactive MidasHandEscrow deploy — stdout is JSON only.
# Invoked by acton-worker on Ubuntu (POST /deploy-midas-escrow) or via
# ACTON_DEPLOY_CMD locally.
#
# Required env: network (testnet|mainnet), DEPLOYER, MH_WHALE, MH_OWNER,
# MH_MINTER, MH_ADMIN, MH_ROUTER, MH_POOL, MH_PTON_MASTER, MH_LP_WALLET_CODE,
# MH_PTON_WALLET_CODE. Optional: MH_PROPOSAL_TIMEOUT_SEC (default 604800).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-testnet}}"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if ! "$ACTON" script scripts/deploy-midas-escrow.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton midas escrow deploy failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

ESCROW="$(grep -oP 'MIDAS ESCROW_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"

if [[ -z "$ESCROW" ]]; then
  echo "{\"error\":\"missing escrow_address in acton log\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

if [[ -z "$TX" ]]; then
  TX="deploy-${ESCROW}"
fi

python3 - <<PY
import json
print(json.dumps({
    "escrow_address": "${ESCROW}",
    "deploy_tx_hash": "${TX}",
}))
PY
