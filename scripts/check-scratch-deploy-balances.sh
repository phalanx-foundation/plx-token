#!/usr/bin/env bash
# Print TON balances: scratch payout wallet vs deploy gas wallet (no secrets in output).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
python3 - <<'PY'
import json, os, urllib.request

token = os.environ.get("TONAPI_KEY") or os.environ.get("CONSOLE_TOKEN") or ""
for name in ("SCRATCH_PAYOUT_ADDRESS", "JETTON_DEPLOYER_ADDRESS_MAINNET"):
    addr = os.environ.get(name, "").strip()
    if not addr:
        print(f"{name}: not set")
        continue
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    bal = int(data.get("balance", 0)) / 1e9
    print(f"{name}: {bal:.4f} TON")
PY
