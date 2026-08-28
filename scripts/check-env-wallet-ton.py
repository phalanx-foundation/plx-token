#!/usr/bin/env python3
import json
import os
import urllib.request


def load_env():
    out = {}
    with open(
        os.path.expanduser("~/services/plx-toolkit-api/.env"), encoding="utf-8"
    ) as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.strip().split("=", 1)
                out[k] = v.strip().strip('"')
    return out


env = load_env()
token = env.get("TONAPI_KEY", "")
headers = {"Authorization": f"Bearer {token}"} if token else {}

addrs = {
    "SCRATCH_PAYOUT env": env.get("SCRATCH_PAYOUT_ADDRESS", ""),
    "DEPLOY env": env.get("JETTON_DEPLOYER_ADDRESS_MAINNET", ""),
    "scratch acton": "kQA_uhzEoNt6C4Xni6vWgGotO2yfkgfIApVyBkPV4umGP66Q",
    "deploy acton": "kQA9M8ojh7ouCnab_HYmDmq0aPoXbI122-atCu8A9NQaRe1r",
}
for label, addr in addrs.items():
    if not addr:
        print(f"{label}: (empty)")
        continue
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}", headers=headers
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    print(f"{label}: {int(data.get('balance', 0)) / 1e9:.4f} TON  {addr[:20]}...")
