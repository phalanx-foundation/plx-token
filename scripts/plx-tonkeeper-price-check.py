#!/usr/bin/env python3
"""Probe Tonkeeper USD gates — TonAPI rates, holders, pool TON. Writes data/tonkeeper-price-probe.json."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.listing_checks import (  # noqa: E402
    check_dexscreener_pair,
    check_stonfi_pool_ton,
    check_tonapi_jetton,
    check_tonapi_rates,
    now_iso,
    tonapi_price_gates,
)

OUT = Path(ROOT / "data" / "tonkeeper-price-probe.json")


from lib.listing_pack import STONFI_POOL_URL  # noqa: E402

LP_WALLET = "EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH"
TREASURY_WALLET = "EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX"
COMMUNITY_WALLET = "EQD1XDv0Awjx0GUVv6YQYYnvEmjcKJ9iEBjvtHPM2nWML-q9"


def _account_ton_human(address: str) -> float | None:
    from lib.listing_checks import _http_json  # noqa: PLC0415

    data = _http_json(f"https://tonapi.io/v2/accounts/{address}")
    if not data or "balance" not in data:
        return None
    try:
        return int(data["balance"]) / 1e9
    except (TypeError, ValueError):
        return None


def main() -> int:
    ton = check_tonapi_jetton()
    rates = check_tonapi_rates()
    ds = check_dexscreener_pair()
    stonfi = check_stonfi_pool_ton()
    pool_ton = ds.get("pool_ton_quote") or stonfi.get("ton_human")
    gates = tonapi_price_gates(
        holders=ton.get("holders") if isinstance(ton.get("holders"), int) else None,
        pool_ton_quote=pool_ton,
        usd_price=float(rates.get("usd") or 0),
    )
    result = {
        "at": now_iso(),
        "tonapi_jetton": ton,
        "tonapi_rates": rates,
        "dexscreener_pair": ds,
        "stonfi_pool": stonfi,
        "gates": gates,
        "tonkeeper_usd_ready": gates.get("tonkeeper_usd_ready"),
        "wallet_ton_balances": {
            "plx_lp": _account_ton_human(LP_WALLET),
            "plx_treasury": _account_ton_human(TREASURY_WALLET),
            "plx_community": _account_ton_human(COMMUNITY_WALLET),
        },
        "deepen_lp_blockers": {
            "need_ton_on_lp": max(0.0, gates.get("min_ton_reserve", 100) - float(pool_ton or 0)),
            "lp_wallet_ton": _account_ton_human(LP_WALLET),
            "stonfi_pool_url": STONFI_POOL_URL,
        },
        "holder_growth": {
            "holders": gates.get("holders"),
            "need_holders": max(0, gates.get("min_holders", 100) - int(gates.get("holders") or 0)),
            "airdrop_queue": "data/airdrop-season-queue.json",
            "template": "data/holder-growth-queue.template.json",
        },
        "runbook": "docs/TONKEEPER-USD-PRICE-RUNBOOK.md",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if gates.get("tonkeeper_usd_ready") else 1


if __name__ == "__main__":
    sys.exit(main())
