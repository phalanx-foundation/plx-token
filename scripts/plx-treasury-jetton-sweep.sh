#!/usr/bin/env bash
# Non-interactive PLX jetton treasury sweep — stdout is JSON only.
# Invoked by acton-worker POST /plx-treasury-sweep.
#
# Required env: network, PLX_SWEEP_AMOUNT_NANO (treasury slice = half of client payment),
#               DEPLOYMENT_ID, JETTON_MINTER_ADDRESS
# Split treasury slice: 40% LP, 30% marketing, 30% ops (= 20/15/15 of total fee)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-mainnet}}"

SWEEP_RAW="${PLX_SWEEP_AMOUNT_NANO:-0}"
SWEEP_CLEAN="${SWEEP_RAW//,/}"
if ! [[ "$SWEEP_CLEAN" =~ ^[0-9]+$ ]] || [[ "$SWEEP_CLEAN" -le 0 ]]; then
  echo '{"error":"invalid PLX_SWEEP_AMOUNT_NANO"}' >&2
  exit 1
fi

# 40/30/30 of treasury slice (20/15/15 of total client payment)
LP_NANO=$((SWEEP_CLEAN * 40 / 100))
MARKETING_NANO=$((SWEEP_CLEAN * 30 / 100))
OPS_NANO=$((SWEEP_CLEAN - LP_NANO - MARKETING_NANO))

if [[ "$LP_NANO" -le 0 ]] || [[ "$MARKETING_NANO" -le 0 ]] || [[ "$OPS_NANO" -le 0 ]]; then
  echo '{"error":"PLX_SWEEP_AMOUNT_NANO too small for 40/30/30 split"}' >&2
  exit 1
fi

export PLX_SWEEP_LP_NANO="$LP_NANO"
export PLX_SWEEP_MARKETING_NANO="$MARKETING_NANO"
export PLX_SWEEP_OPS_NANO="$OPS_NANO"
export FROM_WALLET="${FROM_WALLET:-plx-treasury}"
export DEPLOYMENT_ID="${DEPLOYMENT_ID:-unknown}"

if [[ -z "${JETTON_MINTER_ADDRESS:-}" ]]; then
  if [[ "$NETWORK" == "mainnet" ]]; then
    export JETTON_MINTER_ADDRESS="${PLX_JETTON_MINTER_MAINNET:-EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS}"
  else
    export JETTON_MINTER_ADDRESS="${PLX_JETTON_MINTER:-kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV}"
  fi
fi

if [[ "$NETWORK" == "testnet" ]]; then
  export PLX_LP_ADDRESS="${PLX_LP_ADDRESS:-kQD4-ER4sDGmw4PcPPJ-AwLYG9TORvZ5sJ-xNKthunKz0AOP}"
  export PLX_MARKETING_ADDRESS="${PLX_MARKETING_ADDRESS:-kQD51illBEG2sQ5do-28UoVDyiQbyRMVagzfwnWV7QCginMA}"
  export PLX_TOOLKIT_OPS_ADDRESS="${PLX_TOOLKIT_OPS_ADDRESS:-kQAZWyvZBkUctnlbqP8EVTzh43g7JcYod9NqYjenRbf2nPiC}"
else
  export PLX_LP_ADDRESS="${PLX_LP_ADDRESS:-EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH}"
  export PLX_MARKETING_ADDRESS="${PLX_MARKETING_ADDRESS:-EQDB9yVhkPvEhMFo90fqHWzqYj2mESAlwObMbA6LX7fETtN6}"
  export PLX_TOOLKIT_OPS_ADDRESS="${PLX_TOOLKIT_OPS_ADDRESS:-EQC5X2oWTI5NjFB9GIZ_8iWqGdhhiGsXY-SiLe42iZK4nvHK}"
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

if ! "$ACTON" script scripts/plx-treasury-jetton-sweep.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton plx-treasury-sweep failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

TX_HASHES="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | tr '\n' ',' | sed 's/,$//' || true)"

python3 - <<PY
import json, os
print(json.dumps({
    "deployment_id": "${DEPLOYMENT_ID}",
    "plx_sweep_amount_nano": int("${SWEEP_CLEAN}"),
    "plx_sweep_lp_nano": int("${LP_NANO}"),
    "plx_sweep_marketing_nano": int("${MARKETING_NANO}"),
    "plx_sweep_ops_nano": int("${OPS_NANO}"),
    "plx_sweep_tx_hashes": [h for h in "${TX_HASHES}".split(",") if h],
    "payment_linked": True,
    "payment_tx_hash": os.environ.get("PAYMENT_TX_HASH") or None,
    "payment_sender_address": os.environ.get("PAYMENT_SENDER_ADDRESS") or None,
}))
PY
