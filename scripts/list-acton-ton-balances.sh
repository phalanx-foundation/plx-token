#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.acton/bin:$PATH"
cd ~/projects/plx-acton
API_ENV=~/services/plx-toolkit-api/.env
export TONAPI_KEY=$(awk -F= '/^TONAPI_KEY=/{print substr($0,index($0,"=")+1)}' "$API_ENV" | tr -d '\r')
python3 - <<'PY'
import json, os, subprocess, urllib.request

token = os.environ.get("TONAPI_KEY") or ""
out = subprocess.check_output(["acton", "wallet", "list"], text=True, stderr=subprocess.DEVNULL)
rows = []
for line in out.splitlines():
    parts = line.split()
    if len(parts) < 2:
        continue
    name, addr = parts[0], parts[1]
    if not addr.startswith(("kQ", "EQ", "UQ")):
        continue
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    bal = int(data.get("balance", 0)) / 1e9
    if bal >= 0.001:
        rows.append((bal, name, addr))
for bal, name, addr in sorted(rows, reverse=True):
    print(f"{bal:>12.4f} TON  {name}  {addr}")
PY
