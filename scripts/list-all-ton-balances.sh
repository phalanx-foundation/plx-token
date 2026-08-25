#!/usr/bin/env bash
set -euo pipefail
API_ENV=~/services/plx-toolkit-api/.env
export TONAPI_KEY=$(awk -F= '/^TONAPI_KEY=/{print substr($0,index($0,"=")+1)}' "$API_ENV" | tr -d '\r')
export SCRATCH_PAYOUT_ADDRESS=$(awk -F= '/^SCRATCH_PAYOUT_ADDRESS=/{print substr($0,index($0,"=")+1)}' "$API_ENV" | tr -d '\r')
export JETTON_DEPLOYER_ADDRESS_MAINNET=$(awk -F= '/^JETTON_DEPLOYER_ADDRESS_MAINNET=/{print substr($0,index($0,"=")+1)}' "$API_ENV" | tr -d '\r')
export PATH="$HOME/.acton/bin:$PATH"
cd ~/projects/plx-acton
python3 - <<'PY'
import json, os, subprocess, urllib.request

token = os.environ.get("TONAPI_KEY") or ""

def bal(addr: str) -> float:
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    return int(data.get("balance", 0)) / 1e9

print("=== Configured addresses ===")
for label in ("SCRATCH_PAYOUT_ADDRESS", "JETTON_DEPLOYER_ADDRESS_MAINNET"):
    addr = os.environ.get(label, "").strip()
    if addr:
        print(f"{label}: {bal(addr):.6f} TON")

print("\n=== Acton wallets (any balance) ===")
out = subprocess.check_output(["acton", "wallet", "list"], text=True, stderr=subprocess.DEVNULL)
for line in out.splitlines():
    parts = line.split()
    if len(parts) < 2 or not parts[1].startswith(("kQ", "EQ", "UQ")):
        continue
    name, addr = parts[0], parts[1]
    b = bal(addr)
    print(f"{b:>12.6f} TON  {name}")
PY
