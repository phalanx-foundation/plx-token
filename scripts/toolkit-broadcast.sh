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
# Advanced templates (fee/antiwhale/staking/airdrop) use the combo script so the
# buyer really gets the contract they paid for instead of a plain jetton.
ALLOC_COUNT="${JETTON_ALLOC_COUNT:-0}"
JETTON_TEMPLATE_NORM="$(printf '%s' "${JETTON_TEMPLATE:-standard}" | tr '[:upper:]' '[:lower:]')"
case "$JETTON_TEMPLATE_NORM" in
  fee|antiwhale|staking|airdrop)
    if [[ "$ALLOC_COUNT" =~ ^[0-9]+$ && "$ALLOC_COUNT" -gt 0 ]]; then
      echo '{"error":"advanced template with multi-wallet allocations is not supported"}' >&2
      exit 1
    fi
    DEPLOY_SCRIPT="scripts/deploy-jetton-combo.tolk"
    ;;
  *)
    if [[ "$ALLOC_COUNT" =~ ^[0-9]+$ && "$ALLOC_COUNT" -gt 0 ]]; then
      DEPLOY_SCRIPT="scripts/deploy-distribution-client.tolk"
    else
      DEPLOY_SCRIPT="scripts/deploy-client-jetton.tolk"
    fi
    ;;
esac

if ! "$ACTON" script "$DEPLOY_SCRIPT" --net "$NETWORK" >"$LOG" 2>&1; then
  # deploy-jetton-combo.tolk prints the fail-closed reason as TOOLKIT ERROR=...
  # Surface it instead of a generic message so the buyer sees what to fix.
  REASON="$(grep -oP 'TOOLKIT ERROR=\K.*' "$LOG" | tail -1 | tr -d '"\\' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//' || true)"
  TAIL="$(tail -c 500 "$LOG" | tr -d '"\\' | tr '\n' ' ' || true)"
  printf '{"error":"%s","log_tail":"%s"}\n' "${REASON:-acton deploy failed}" "$TAIL" >&2
  exit 1
fi

MINTER="$(grep -oP 'TOOLKIT MINTER_ADDRESS=\K\S+' "$LOG" | tail -1 || true)"
TX="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | head -1 || true)"
PENDING="$(grep -oP 'TOOLKIT PENDING_ADMIN_CLAIM=\K\S+' "$LOG" | tail -1 || true)"
# Collect deployed vesting contract addresses (distribution buckets with lock).
VESTING_ADDRS="$(grep -oP 'TOOLKIT ALLOC_VESTING=\K\S+' "$LOG" || true)"
# Staking / airdrop companion deployed by deploy-jetton-combo.tolk, so the client
# can actually find the contract they paid for.
COMPANION="$(grep -oP 'TOOLKIT COMPANION_CONTRACT=\K\S+' "$LOG" | tail -1 || true)"

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

MINTER="$MINTER" TX="$TX" PENDING="$PENDING" VESTING_ADDRS="$VESTING_ADDRS" \
  COMPANION="$COMPANION" TEMPLATE="$JETTON_TEMPLATE_NORM" python3 - <<'PY'
import json, os
vesting = [a for a in os.environ.get("VESTING_ADDRS", "").split() if a.strip()]
print(json.dumps({
    "template": os.environ.get("TEMPLATE", "standard"),
    "minter_address": os.environ["MINTER"],
    "deploy_tx_hash": os.environ["TX"],
    "pending_admin_claim": os.environ.get("PENDING") == "true",
    "vesting_contracts": vesting,
    "companion_contract": os.environ.get("COMPANION") or None,
}))
PY
