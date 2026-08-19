#!/usr/bin/env bash

# MCP alternative for agent sessions:
#   ton_transfer_jetton via MCP can be used as an alternative to
#   `acton script transfer.tolk` when running from an AI agent session.
#   Acton CLI remains the primary production path.
# Scratch Seeker winner payout — PLX jetton or TON from plx-scratch-seeker-payment.
# Invoked by acton-worker POST /scratch-payout (stdout = JSON only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"
NETWORK="${network:-${NETWORK:-mainnet}}"
ASSET="$(echo "${asset:-${ASSET:-PLX}}" | tr '[:lower:]' '[:upper:]')"
RECIPIENT="${to_address:-${JETTON_TRANSFER_RECIPIENT:-}}"
AMOUNT_NANO="${amount_nano:-${JETTON_TRANSFER_AMOUNT:-}}"
FROM_WALLET="${wallet_name:-${JETTON_SENDER:-plx-scratch-seeker-payment}}"
BET_ID="${bet_id:-unknown}"
DIGITS="${digits:-0}"

if [[ -z "$RECIPIENT" || -z "$AMOUNT_NANO" ]]; then
  echo '{"error":"to_address/amount_nano required"}' >&2
  exit 1
fi

# Human amount for Acton promptJettonCoins (nano / 1e9 for PLX/TON 9dp)
AMOUNT_HUMAN="$(python3 - <<PY
nano=int("${AMOUNT_NANO}")
print(f"{nano / 1e9:.9f}".rstrip("0").rstrip(".") or "0")
PY
)"

set +e
if [[ "$ASSET" == "PLX" ]]; then
  export JETTON_SENDER="$FROM_WALLET"
  export JETTON_TRANSFER_RECIPIENT="$RECIPIENT"
  export JETTON_TRANSFER_AMOUNT="$AMOUNT_HUMAN"
  if [[ "$NETWORK" == "mainnet" ]]; then
    export JETTON_MINTER_ADDRESS="${JETTON_MINTER_ADDRESS:-${PLX_JETTON_MINTER_MAINNET:-EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS}}"
  else
    export JETTON_MINTER_ADDRESS="${JETTON_MINTER_ADDRESS:-${PLX_JETTON_MINTER:-kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV}}"
  fi
  OUT="$("$ACTON" script scripts/transfer.tolk --net "$NETWORK" 2>&1)"
  CODE=$?
elif [[ "$ASSET" == "TON" ]]; then
  export FROM_WALLET="$FROM_WALLET"
  export TO_ADDRESS="$RECIPIENT"
  export TON_AMOUNT_NANO="$AMOUNT_NANO"
  OUT="$("$ACTON" script scripts/send-ton.tolk --net "$NETWORK" 2>&1)"
  CODE=$?
elif [[ "$ASSET" == "USDT" ]]; then
  export JETTON_SENDER="$FROM_WALLET"
  export JETTON_TRANSFER_RECIPIENT="$RECIPIENT"
  export JETTON_TRANSFER_AMOUNT="$AMOUNT_HUMAN"
  export JETTON_MINTER_ADDRESS="${SCRATCH_USDT_MASTER:-${USDT_JETTON_MINTER_MAINNET:-EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs}}"
  OUT="$("$ACTON" script scripts/transfer.tolk --net "$NETWORK" 2>&1)"
  CODE=$?
else
  echo "{\"error\":\"unsupported asset for scratch payout: $ASSET\"}" >&2
  exit 1
fi
set -e

if [[ "$CODE" -ne 0 ]]; then
  python3 - <<'PY' "$OUT"
import json, sys
print(json.dumps({"error": "acton scratch payout failed", "detail": sys.argv[1][-800:]}))
PY
  exit 1
fi

python3 - <<'PY' "$OUT" "$BET_ID" "$RECIPIENT" "$AMOUNT_NANO" "$ASSET" "$DIGITS"
import json, re, sys
stdout, bet_id, recipient, amount, asset, digits = sys.argv[1:7]
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
    "status": "done",
    "bet_id": bet_id,
    "recipient": recipient,
    "asset": asset,
    "digits": int(digits) if str(digits).isdigit() else digits,
    "amount_nano": amount,
    "tx_hash": tx_hash,
    "stdout_tail": stdout[-400:],
}))
PY
