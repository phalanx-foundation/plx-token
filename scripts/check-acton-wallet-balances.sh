#!/usr/bin/env bash
set -euo pipefail
API_ENV=~/services/plx-toolkit-api/.env
export TONAPI_KEY=$(awk -F= '/^TONAPI_KEY=/{print substr($0,index($0,"=")+1)}' "$API_ENV" | tr -d '\r')
export PATH="$HOME/.acton/bin:$PATH"
cd ~/projects/plx-acton
SCRATCH_ACTON=$(acton wallet list 2>/dev/null | awk '/plx-scratch-seeker-payment/ {print $2}')
DEPLOY_ACTON=$(acton wallet list 2>/dev/null | awk '/toolkit-deployer-mainnet/ {print $2}')
export SCRATCH_ACTON DEPLOY_ACTON
python3 - <<PY
import json, os, urllib.request
token = os.environ.get("TONAPI_KEY") or ""
addrs = {
    "plx-scratch-seeker-payment (acton)": os.environ.get("SCRATCH_ACTON", ""),
    "toolkit-deployer-mainnet (acton)": os.environ.get("DEPLOY_ACTON", ""),
}
for label, addr in addrs.items():
    if not addr:
        print(f"{label}: missing")
        continue
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    print(f"{label}: {int(data.get('balance',0))/1e9:.4f} TON")
PY
