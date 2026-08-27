#!/usr/bin/env python3
"""Lazy multi-token listing monitor — only probes when active listings exist.

Triggered BY the deploy hook (not cron). Optional lightweight cron:
  0 */6 * * * cd ~/projects/plx-acton && python3 scripts/toolkit-listing-monitor.py

Early exit: probes NO APIs if DB has zero active listings (status in
{pending, yaml_generated, pr_submitted}). Safe to cron without waste.

Requires: DATABASE_URL, TONAPI_KEY, gh CLI (for PR status checks).
Optional: TOKEN_TELEGRAM_BOT for alerts.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import sqlalchemy as sa
from sqlalchemy import text
from sqlalchemy.orm import Session

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.dotenv_load import load_project_dotenv

load_project_dotenv()

from lib.listing_checks import (
    check_cryptorank_listed,
    check_dexscreener_pair,
    check_stonfi_pool_ton,
    check_ton_assets_pr,
    check_tonapi_jetton,
    check_tonapi_rates,
    now_iso,
)
from lib.listing_notify import send_telegram, telegram_configured
from lib.listing_pack import TokenListingConfig

LOG_FILE = Path(
    os.environ.get("LISTING_LOG_FILE", ROOT / "data" / "listing-monitor-log.json")
)

ACTIVE_STATES = {"pending", "yaml_generated", "pr_submitted"}


def _append_log(entry: dict[str, Any]) -> None:
    logs = []
    if LOG_FILE.exists():
        try:
            logs = json.loads(LOG_FILE.read_text())
            logs = logs if isinstance(logs, list) else []
        except json.JSONDecodeError:
            logs = []
    logs.append(entry)
    if len(logs) > 500:
        logs = logs[-500:]
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    LOG_FILE.write_text(json.dumps(logs, indent=2) + "\n")


def _get_db_session() -> Session:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError("DATABASE_URL not set")
    engine = sa.create_engine(url, pool_pre_ping=True)
    return Session(engine)


def _load_active_listings(db: Session) -> list[dict[str, Any]]:
    rows = db.execute(
        text(
            "SELECT id, deployment_id, minter_address, pool_address, "
            "listing_status, ton_assets_pr_number, ton_assets_pr_url, "
            "tonapi_verification, holders_count, pool_ton_quote, "
            "coingecko_submitted, coingecko_id, cmc_submitted, tonapi_rates_usd, "
            "cryptorank_submitted, cryptorank_id, cryptorank_slug "
            "FROM token_listings WHERE listing_status = ANY(:states)"
        ),
        {"states": list(ACTIVE_STATES)},
    ).fetchall()

    return [
        {
            "id": r[0],
            "deployment_id": r[1],
            "minter_address": r[2],
            "pool_address": r[3],
            "listing_status": r[4],
            "ton_assets_pr_number": r[5],
            "ton_assets_pr_url": r[6],
            "tonapi_verification": r[7],
            "holders_count": r[8],
            "pool_ton_quote": r[9],
            "coingecko_submitted": r[10],
            "coingecko_id": r[11],
            "cmc_submitted": r[12],
            "tonapi_rates_usd": r[13],
            "cryptorank_submitted": r[14],
            "cryptorank_id": r[15],
            "cryptorank_slug": r[16],
        }
        for r in rows
    ]


def _update_listing(db: Session, listing_id: str, fields: dict[str, Any]) -> None:
    set_clauses = []
    params = {"id": listing_id}
    for key, val in fields.items():
        if val is not None:
            set_clauses.append(f"{key} = :{key}")
            params[key] = val
    if not set_clauses:
        return
    set_clauses.append("last_probe_at = :now")
    params["now"] = datetime.now(timezone.utc)
    sql = f"UPDATE token_listings SET {', '.join(set_clauses)} WHERE id = :id"
    db.execute(text(sql), params)
    db.commit()


def _probe_one(row: dict[str, Any]) -> dict[str, Any]:
    cfg = TokenListingConfig(
        name="",
        symbol="",
        minter_address=row["minter_address"],
        pool_address=row["pool_address"] or "",
        ton_assets_pr=row["ton_assets_pr_number"],
    )

    ton = check_tonapi_jetton(cfg)
    rates = check_tonapi_rates(cfg)

    fields: dict[str, Any] = {
        "tonapi_verification": ton.get("verification"),
        "holders_count": ton.get("holders")
        if isinstance(ton.get("holders"), int)
        else None,
        "tonapi_rates_usd": rates.get("usd"),
    }

    if cfg.pool_address:
        stonfi = check_stonfi_pool_ton(cfg)
        ds = check_dexscreener_pair(cfg)
        pool_ton = ds.get("pool_ton_quote")
        if pool_ton is None and stonfi.get("ton_human") is not None:
            pool_ton = stonfi.get("ton_human")
        fields["pool_ton_quote"] = pool_ton

    if row["ton_assets_pr_number"]:
        pr = check_ton_assets_pr(cfg)
        if pr.get("state"):
            fields["ton_assets_pr_state"] = pr["state"]
        if pr.get("merged"):
            fields["listing_status"] = "whitelist"
            fields["ton_assets_pr_state"] = "MERGED"

    # CoinGecko / CMC eligibility checks
    from lib.listing_pack import CMC_MIN_LP_USD, COINGECKO_MIN_LP_USD

    rates_usd = fields.get("tonapi_rates_usd") or row.get("tonapi_rates_usd")
    pool_ton = fields.get("pool_ton_quote") or row.get("pool_ton_quote")

    if rates_usd and pool_ton:
        try:
            fiat_lp = float(pool_ton) * float(rates_usd)
            if fiat_lp >= COINGECKO_MIN_LP_USD and not row.get("coingecko_submitted"):
                fields["coingecko_eligible"] = True
            if fiat_lp >= CMC_MIN_LP_USD and not row.get("cmc_submitted"):
                fields["cmc_eligible"] = True
        except (TypeError, ValueError):
            pass

    # CryptoRank: if submitted (or always best-effort), probe for live listing id/slug
    if row.get("cryptorank_submitted") and not row.get("cryptorank_id") and not row.get(
        "cryptorank_slug"
    ):
        cr = check_cryptorank_listed(cfg)
        if cr.get("listed"):
            fields["cryptorank_id"] = cr.get("cryptorank_id")
            fields["cryptorank_slug"] = cr.get("cryptorank_slug")
            if cr.get("url"):
                fields["cryptorank_url"] = cr.get("url")

    return fields


def main() -> int:
    db = _get_db_session()
    try:
        rows = _load_active_listings(db)
    finally:
        db.close()

    if not rows:
        print(
            json.dumps({"ok": True, "active_listings": 0, "note": "no active — exit"})
        )
        return 0

    run_log = {"at": now_iso(), "active": len(rows), "results": []}

    for row in rows:
        try:
            fields = _probe_one(row)
        except Exception as exc:
            fields = {"last_error": f"probe_exception: {exc}"}

        try:
            db2 = _get_db_session()

            # Remove non-DB fields before UPDATE
            fields.pop("coingecko_eligible", None)
            fields.pop("cmc_eligible", None)

            _update_listing(db2, row["id"], fields)
            db2.close()
        except Exception as exc:
            run_log["db_error"] = str(exc)

        # CoinGecko / CMC submission trigger
        if fields.get("coingecko_eligible"):
            fields["coingecko_submitted"] = True
            run_log.setdefault("coingecko_notes", []).append(
                "CG eligible: {} LP=${}".format(
                    row["minter_address"], fields.get("pool_ton_quote", "?")
                )
            )
        if fields.get("cmc_eligible"):
            fields["cmc_submitted"] = True
            run_log.setdefault("cmc_notes", []).append(
                "CMC eligible: {} LP=${}".format(
                    row["minter_address"], fields.get("pool_ton_quote", "?")
                )
            )

        # Telegram alert if whitelist but USD still 0
        verification = fields.get("tonapi_verification") or row.get(
            "tonapi_verification"
        )
        usd = fields.get("tonapi_rates_usd") or row.get("tonapi_rates_usd")
        if (
            telegram_configured()
            and verification == "whitelist"
            and (usd is None or float(usd) <= 0)
        ):
            holders = fields.get("holders_count") or row.get("holders_count") or 0
            pool = fields.get("pool_ton_quote") or row.get("pool_ton_quote") or 0
            send_telegram(
                f"Tonkeeper USD blocked for {row['minter_address']}\n\n"
                f"Verification: whitelist | Rates USD: {usd}\n"
                f"Holders: {holders} | Pool TON: {float(pool):.1f}\n"
                "Deepen LP + grow holders."
            )

        run_log["results"].append(
            {
                "row_id": row["id"],
                "minter": row["minter_address"],
                "status_before": row["listing_status"],
                "updated": {k: v for k, v in fields.items() if v is not None},
            }
        )

    _append_log(run_log)
    print(json.dumps({"ok": True, "run": run_log}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
