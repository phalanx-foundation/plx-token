from database import SessionLocal
from models import ScratchVaultBalance

db = SessionLocal()
for v in db.query(ScratchVaultBalance).all():
    bal = int(v.balance_nano or 0) / 1e9
    print(f"{v.vault_key}: {bal:.4f} {v.asset}")
db.close()
