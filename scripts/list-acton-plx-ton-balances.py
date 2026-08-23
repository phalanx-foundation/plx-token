#!/usr/bin/env python3
"""PLX + TON balances for Acton wallets (reads API .env for TONAPI_KEY + minter)."""
from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.request

ENV_PATH = os.path.expanduser("~/services/plx-toolkit-api/.env")
ACTON = os.path.expanduser("~/.acton/bin/acton")
ACTON_CWD = os.path.expanduser("~/projects/plx-acton")


def load_env() -> dict[str, str]:
    out: dict[str, str] = {}
    if os.path.isfile(ENV_PATH):
        with open(ENV_PATH, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


env = load_env()
token = env.get("TONAPI_KEY", "")
minter = env.get("PLX_MINTER_MAINNET") or env.get("PLX_MINTER_ADDRESS", "")

out = subprocess.check_output([ACTON, "wallet", "list"], cwd=ACTON_CWD, text=True)
wallets: list[tuple[str, str]] = []
for line in out.splitlines():
    parts = line.split()
    if len(parts) >= 2 and parts[1].startswith(("kQ", "EQ", "UQ")):
        wallets.append((parts[0], parts[1]))

for name, addr in wallets:
    time.sleep(1.1)
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    req = urllib.request.Request(f"https://tonapi.io/v2/accounts/{addr}", headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        acc = json.load(r)
    ton = int(acc.get("balance", 0)) / 1e9
    plx = 0.0
    if minter:
        time.sleep(1.1)
        req2 = urllib.request.Request(
            f"https://tonapi.io/v2/accounts/{addr}/jettons/{minter}",
            headers=headers,
        )
        try:
            with urllib.request.urlopen(req2, timeout=20) as r2:
                j = json.load(r2)
            plx = int(j.get("balance", 0)) / 1e9
        except urllib.error.HTTPError as e:
            if e.code != 404:
                plx = -1
    if ton >= 0.0001 or plx >= 0.01:
        print(f"{name}: {ton:.4f} TON, {plx:.2f} PLX")
