#!/usr/bin/env python3
"""
Cek apakah pair PLX masih terindeks DexScreener + saran tindakan.

Tidak melakukan swap otomatis — hanya diagnosa. Untuk swap otomatis pakai
plx-branding-swap.py (Acton server, wallet funded).

Cron contoh (1x/hari):
  0 8 * * * cd ~/projects/plx-acton && python3 scripts/plx-dex-heartbeat-check.py

Exit code: 0 = terindeks OK, 1 = de-indexed / perlu aktivitas swap
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.dotenv_load import load_project_dotenv  # noqa: E402

load_project_dotenv()

from lib.listing_checks import check_dexscreener_pair  # noqa: E402
from lib.listing_pack import STONFI_POOL_URL  # noqa: E402


def _state_path() -> Path:
    import os  # noqa: PLC0415
    return Path(os.environ.get("DEX_HEARTBEAT_STATE", ROOT / "data" / "dex-heartbeat-state.json"))


def main() -> int:
    import os  # noqa: PLC0415 — after dotenv

    dex = check_dexscreener_pair()
    now = datetime.now(timezone.utc).isoformat()
    indexed = bool(dex.get("ok"))
    txns = dex.get("txns_24h") or {}
    buys = int(txns.get("buys") or 0) if isinstance(txns, dict) else 0
    sells = int(txns.get("sells") or 0) if isinstance(txns, dict) else 0
    tx_total = buys + sells

    branding_on = os.environ.get("BRANDING_SWAP_ENABLED", "").lower() == "true"
    listing_branding = os.environ.get("LISTING_RUN_BRANDING", "true").lower() == "true"

    out = {
        "at": now,
        "dexscreener_indexed": indexed,
        "liquidity_usd": dex.get("liquidity_usd"),
        "txns_24h": dex.get("txns_24h"),
        "url": dex.get("url"),
        "stonfi_pool": STONFI_POOL_URL,
        "branding_swap_enabled": branding_on,
        "listing_run_branding": listing_branding,
    }

    if not indexed:
        out["action"] = (
            "DE-INDEXED: lakukan 1 swap kecil di Ston.fi (~0.05–0.1 TON) atau aktifkan "
            "BRANDING_SWAP_ENABLED + LISTING_RUN_BRANDING di server Acton (lihat docs/LISTING-AUTOMATION.md)."
        )
        out["severity"] = "warn"
    elif tx_total == 0:
        out["action"] = (
            "Terindeks tapi 0 tx 24j — pertimbangkan 1 micro-swap atau quest komunitas "
            "agar tidak de-index lagi."
        )
        out["severity"] = "info"
    else:
        out["action"] = "OK — pair aktif di DexScreener."
        out["severity"] = "ok"

    STATE = _state_path()
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if indexed and tx_total > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
