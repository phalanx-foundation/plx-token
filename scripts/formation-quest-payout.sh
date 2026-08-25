#!/usr/bin/env bash
# Formation quest PLX payout — single jetton transfer from community treasury wallet.
# Invoked by acton-worker POST /formation-quest-payout (stdout = JSON only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-mainnet}}"

RECIPIENT="${JETTON_TRANSFER_RECIPIENT:-}"
AMOUNT="${JETTON_TRANSFER_AMOUNT:-}"
FROM="${JETTON_SENDER:-${FORMATION_PAYOUT_FROM_WALLET:-plx-community}}"
COMPLETION_ID="${FORMATION_COMPLETION_ID:-unknown}"

if [[ -z "$RECIPIENT" || -z "$AMOUNT" ]]; then
  echo '{"error":"JETTON_TRANSFER_RECIPIENT and JETTON_TRANSFER_AMOUNT required"}' >&2
  exit 1
fi

export JETTON_SENDER="$FROM"
export JETTON_TRANSFER_RECIPIENT="$RECIPIENT"
export JETTON_TRANSFER_AMOUNT="$AMOUNT"

if [[ "$NETWORK" == "mainnet" ]]; then
  export JETTON_MINTER_ADDRESS="${JETTON_MINTER_ADDRESS:-${PLX_JETTON_MINTER_MAINNET:-EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS}}"
else
  export JETTON_MINTER_ADDRESS="${JETTON_MINTER_ADDRESS:-${PLX_JETTON_MINTER:-kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV}}"
fi

set +e
OUT="$("$ACTON" script scripts/transfer.tolk --net "$NETWORK" 2>&1)"
CODE=$?
set -e

if [[ "$CODE" -ne 0 ]]; then
  python3 - <<'PY' "$OUT"
import json, sys
print(json.dumps({"error": "acton transfer failed", "detail": sys.argv[1][-800:]}))
PY
  exit 1
fi

python3 - <<'PY' "$OUT" "$COMPLETION_ID" "$RECIPIENT" "$AMOUNT"
import json, re, sys
stdout, completion_id, recipient, amount = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
tx_hash = None
for pat in (
    r"transaction(?: hash| id)?[:=]\s*([A-Za-z0-9+/=_-]{32,})",
    r"\b([A-Fa-f0-9]{64})\b",
):
    m = re.search(pat, stdout, re.I)
    if m:
        tx_hash = m.group(1)
        break
print(json.dumps({
    "ok": True,
    "completion_id": completion_id,
    "recipient": recipient,
    "amount_plx": amount,
    "tx_hash": tx_hash,
    "stdout_tail": stdout[-400:],
}))
PY
