from database import SessionLocal
from models import ScratchLedger

db = SessionLocal()
rows = (
    db.query(ScratchLedger)
    .filter(ScratchLedger.vault_key == "ton_usdt_vault")
    .order_by(ScratchLedger.created_at.desc())
    .limit(8)
    .all()
)
print("last ton_usdt_vault ledger rows:")
for r in rows:
    print(
        f"  {r.created_at} {r.direction} {r.entry_type} {int(r.amount_nano or 0) / 1e9:.4f} note={(r.note or '')[:80]}"
    )
db.close()
