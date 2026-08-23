#!/usr/bin/env bash
set -euo pipefail

API_ENV=~/services/plx-toolkit-api/.env
export SCRATCH_PAYOUT_ADDRESS=$(grep ^SCRATCH_PAYOUT_ADDRESS= "$API_ENV" | cut -d= -f2- | tr -d '\r')
export JETTON_DEPLOYER_ADDRESS_MAINNET=$(grep ^JETTON_DEPLOYER_ADDRESS_MAINNET= "$API_ENV" | cut -d= -f2- | tr -d '\r')
export TONAPI_KEY=$(grep ^TONAPI_KEY= "$API_ENV" | cut -d= -f2- | tr -d '\r')

echo "=== On-chain TON (env addresses) ==="
bash ~/projects/plx-acton/scripts/check-scratch-deploy-balances.sh

echo ""
echo "=== On-chain TON (Acton wallet names) ==="
export PATH="$HOME/.acton/bin:$PATH"
SCRATCH_ADDR=$(acton wallet list 2>/dev/null | awk '/plx-scratch-seeker-payment/ {print $2}')
DEPLOY_ADDR=$(acton wallet list 2>/dev/null | awk '/toolkit-deployer-mainnet/ {print $2}')
python3 - <<PY
import json, os, urllib.request
token = os.environ.get("TONAPI_KEY") or ""
for label, addr in [
    ("plx-scratch-seeker-payment", "${SCRATCH_ADDR}"),
    ("toolkit-deployer-mainnet", "${DEPLOY_ADDR}"),
]:
    if not addr:
        print(f"{label}: no address")
        continue
    req = urllib.request.Request(
        f"https://tonapi.io/v2/accounts/{addr}",
        headers={"Authorization": f"Bearer {token}"} if token else {},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    bal = int(data.get("balance", 0)) / 1e9
    print(f"{label}: {bal:.4f} TON")
PY

echo ""
echo "=== Vault ledger ton_usdt_vault ==="
docker exec plx-toolkit-api python3 - <<'PY'
from database import SessionLocal
from services.scratch import vault
from services.scratch.config import VAULT_STABLE

db = SessionLocal()
for v in vault.vault_summary(db):
    if v["vault_key"] == VAULT_STABLE:
        bal = int(v["balance_nano"]) / 1e9
        thr = int(v["low_threshold_nano"]) / 1e9
        print(f"ledger {v['vault_key']}: {bal:.4f} {v['asset']} (low={thr:.4f})")
db.close()
PY
