from database import SessionLocal
from models import ScratchLedger, ScratchVaultBalance
from sqlalchemy import BigInteger, cast, func

db = SessionLocal()
print("=== Vault balances ===")
for v in db.query(ScratchVaultBalance).order_by(ScratchVaultBalance.vault_key).all():
    print(f"{v.vault_key}: {int(v.balance_nano or 0) / 1e9:.4f} (row asset={v.asset})")

for vault_key in ("ton_usdt_vault", "ops_wallet", "plx_vault"):
    print(f"\n=== {vault_key} ledger by asset/type ===")
    rows = (
        db.query(
            ScratchLedger.asset,
            ScratchLedger.entry_type,
            func.sum(cast(ScratchLedger.amount_nano, BigInteger)),
        )
        .filter(ScratchLedger.vault_key == vault_key)
        .group_by(ScratchLedger.asset, ScratchLedger.entry_type)
        .all()
    )
    for asset, etype, total in rows:
        print(f"  {asset} {etype}: {int(total or 0) / 1e9:.4f}")

db.close()
