#!/usr/bin/env bash
# Non-interactive treasury 25/25/25/25 sweep — stdout is JSON only.
# Invoked by acton-worker POST /treasury-sweep or ACTON_SWEEP_CMD locally.
#
# Required env: network, SWEEP_AMOUNT_NANO, DEPLOYMENT_ID
# Optional: PLX_LP_ADDRESS, PLX_MARKETING_ADDRESS, PLX_TOOLKIT_OPS_ADDRESS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-mainnet}}"

SWEEP_RAW="${SWEEP_AMOUNT_NANO:-0}"
SWEEP_CLEAN="${SWEEP_RAW//,/}"
if ! [[ "$SWEEP_CLEAN" =~ ^[0-9]+$ ]] || [[ "$SWEEP_CLEAN" -le 0 ]]; then
  echo '{"error":"invalid SWEEP_AMOUNT_NANO"}' >&2
  exit 1
fi

QUARTER=$((SWEEP_CLEAN / 4))
if [[ "$QUARTER" -le 0 ]]; then
  echo '{"error":"SWEEP_AMOUNT_NANO too small for quarter split"}' >&2
  exit 1
fi

export QUARTER_NANO="$QUARTER"
export FROM_WALLET="${FROM_WALLET:-plx-treasury}"
export DEPLOYMENT_ID="${DEPLOYMENT_ID:-unknown}"

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
LP_JSON="$(mktemp)"
trap 'rm -f "$LOG" "$LP_JSON"' EXIT

# LP slice — Ston.fi simulate + fallback transfer (or queue when pool absent)
export LP_TON_NANO="$QUARTER"
python3 "$ROOT/scripts/stonfi-add-liquidity.py" >"$LP_JSON" 2>/dev/null || echo '{"mode":"lp_failed","ok":false}' >"$LP_JSON"

if ! "$ACTON" script scripts/treasury-sweep.tolk --net "$NETWORK" >"$LOG" 2>&1; then
  echo "{\"error\":\"acton treasury-sweep failed\",\"log_tail\":\"$(tail -c 500 "$LOG" | tr -d '\"\\')\"}" >&2
  exit 1
fi

BUYBACK="$(grep -oP 'SWEEP_BUYBACK_NANO=\K[0-9]+' "$LOG" | tail -1 || true)"
TX_HASHES="$(grep -oE '[A-Fa-f0-9]{64}' "$LOG" | tr '\n' ',' | sed 's/,$//' || true)"

QUEUE_FILE="${BUYBACK_QUEUE_FILE:-$ROOT/data/buyback-pending.json}"
mkdir -p "$(dirname "$QUEUE_FILE")"
python3 - <<PY
import json, os, time
from pathlib import Path

queue_path = Path("${QUEUE_FILE}")
entries = []
if queue_path.exists():
    try:
        entries = json.loads(queue_path.read_text())
        if not isinstance(entries, list):
            entries = []
    except json.JSONDecodeError:
        entries = []

entries.append({
    "deployment_id": os.environ.get("DEPLOYMENT_ID", "unknown"),
    "network": os.environ.get("network", os.environ.get("NETWORK", "mainnet")),
    "buyback_nano": int("${BUYBACK:-0}"),
    "sweep_amount_nano": int("${SWEEP_CLEAN}"),
    "queued_at": int(time.time()),
    "status": "pending",
})
queue_path.write_text(json.dumps(entries, indent=2))
PY

python3 - <<PY
import json, os
from pathlib import Path
lp = json.loads(Path("${LP_JSON}").read_text())
print(json.dumps({
    "deployment_id": "${DEPLOYMENT_ID}",
    "sweep_amount_nano": int("${SWEEP_CLEAN}"),
    "quarter_nano": int("${QUARTER}"),
    "buyback_nano": int("${BUYBACK:-0}"),
    "sweep_tx_hashes": [h for h in "${TX_HASHES}".split(",") if h],
    "buyback_queued": True,
    "lp_slice": lp,
    "payment_linked": True,
    "payment_tx_hash": os.environ.get("PAYMENT_TX_HASH") or None,
    "payment_sender_address": os.environ.get("PAYMENT_SENDER_ADDRESS") or None,
}))
PY
