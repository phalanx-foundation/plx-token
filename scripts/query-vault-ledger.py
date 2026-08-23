from database import SessionLocal
from services.scratch import vault
from services.scratch.config import VAULT_STABLE

db = SessionLocal()
for v in vault.vault_summary(db):
    if v["vault_key"] == VAULT_STABLE:
        bal = int(v["balance_nano"]) / 1e9
        thr = int(v["low_threshold_nano"]) / 1e9
        print(f"ledger {v['vault_key']}: {bal:.4f} {v['asset']} low={thr:.4f}")
db.close()
