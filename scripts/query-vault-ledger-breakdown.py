from database import SessionLocal
from models import ScratchLedger
from sqlalchemy import BigInteger, cast, func

db = SessionLocal()
rows = (
    db.query(
        ScratchLedger.asset,
        ScratchLedger.entry_type,
        func.sum(cast(ScratchLedger.amount_nano, BigInteger)),
    )
    .filter(ScratchLedger.vault_key == "ton_usdt_vault")
    .group_by(ScratchLedger.asset, ScratchLedger.entry_type)
    .all()
)
for asset, etype, total in rows:
    print(f"{asset} {etype}: {int(total or 0) / 1e9:.4f}")
db.close()
