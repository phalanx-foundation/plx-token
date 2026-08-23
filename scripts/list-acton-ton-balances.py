#!/usr/bin/env python3
"""List Acton wallet TON balances (uses TONAPI_KEY from env)."""
from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.request

ACTON = os.environ.get("ACTON", os.path.expanduser("~/.acton/bin/acton"))
ACTON_CWD = os.environ.get("ACTON_CWD", os.path.expanduser("~/projects/plx-acton"))
def _load_tonapi_key() -> str:
    key = os.environ.get("TONAPI_KEY", "").strip()
    if key:
        return key
    env_path = os.path.expanduser("~/services/plx-toolkit-api/.env")
    if os.path.isfile(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("TONAPI_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


token = _load_tonapi_key()

out = subprocess.check_output([ACTON, "wallet", "list"], cwd=ACTON_CWD, text=True)
addrs: list[tuple[str, str]] = []
for line in out.splitlines():
    parts = line.split()
    if len(parts) >= 2 and parts[1].startswith(("kQ", "EQ", "UQ")):
        addrs.append((parts[0], parts[1]))

rows: list[tuple[float, str, str]] = []
for name, addr in addrs:
    time.sleep(1.1)
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    bal = int(data.get("balance", 0)) / 1e9
    rows.append((bal, name, addr))

for bal, name, addr in sorted(rows, reverse=True):
    print(f"{bal:>12.4f} TON  {name}  {addr}")
