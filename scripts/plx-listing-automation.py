#!/usr/bin/env python3
"""
Automated PLX listing / discoverability pipeline (no manual checklist).

Cron (Ubuntu Acton, every 6h):
  0 */6 * * * cd ~/projects/plx-acton && python3 scripts/plx-listing-automation.py >> logs/listing-automation.log 2>&1

GitHub Actions: .github/workflows/listing-automation.yml (schedule + manual dispatch)

Requires: LISTING_AUTOMATION_ENABLED=true
Optional: TOKEN_TELEGRAM_BOT, TONAPI_KEY, gh CLI for ton-assets PR nudge
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.dotenv_load import load_project_dotenv  # noqa: E402

load_project_dotenv()

from lib.listing_checks import (  # noqa: E402
    check_coingecko_listed,
    check_dexscreener_orders,
    check_dexscreener_pair,
    check_dyor_indexed,
    check_stonfi_pool_ton,
    check_tonapi_jetton,
    check_tonapi_rates,
    check_ton_assets_pr,
    eligibility_gates,
    now_iso,
    nudge_ton_assets_pr_if_stale,
    tonapi_price_gates,
)
from lib.listing_notify import send_telegram, telegram_configured  # noqa: E402
from lib.listing_pack import QUEST_MESSAGE, TOKEN_PAGE  # noqa: E402

STATE_FILE = Path(
    os.environ.get(
        "LISTING_STATE_FILE", ROOT / "data" / "listing-automation-state.json"
    )
)
LOG_FILE = Path(
    os.environ.get("LISTING_LOG_FILE", ROOT / "data" / "listing-automation-log.json")
)


def _enabled() -> bool:
    return os.environ.get("LISTING_AUTOMATION_ENABLED", "").lower() == "true"


def _load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {
            "runs": [],
            "last_quest_post": None,
            "last_pr_nudge": None,
            "last_summary_sent": None,
            "last_marketing_run": None,
        }
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {
            "runs": [],
            "last_quest_post": None,
            "last_pr_nudge": None,
            "last_summary_sent": None,
            "last_marketing_run": None,
        }


def _save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def _append_log(entry: dict[str, Any]) -> None:
    logs: list = []
    if LOG_FILE.exists():
        try:
            raw = json.loads(LOG_FILE.read_text())
            logs = raw if isinstance(raw, list) else []
        except json.JSONDecodeError:
            logs = []
    logs.append(entry)
    if len(logs) > 200:
        logs = logs[-200:]
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    LOG_FILE.write_text(json.dumps(logs, indent=2) + "\n")


def _days_since(ts: str | None) -> float:
    if not ts:
        return 999.0
    try:
        then = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - then).total_seconds() / 86400
    except ValueError:
        return 999.0


def _run_branding_swap() -> dict[str, Any]:
    if os.environ.get("LISTING_RUN_BRANDING", "true").lower() != "true":
        return {"skipped": "LISTING_RUN_BRANDING false"}
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "plx-branding-swap.py")],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        env=os.environ.copy(),
        timeout=180,
        check=False,
    )
    out = proc.stdout.strip() or proc.stderr.strip()
    try:
        parsed = json.loads(proc.stdout)
    except json.JSONDecodeError:
        parsed = {"raw": out[:500]}
    return {"exit": proc.returncode, "result": parsed}


def _post_quest_if_due(state: dict[str, Any], interval_days: float) -> dict[str, Any]:
    if os.environ.get("LISTING_QUEST_ENABLED", "true").lower() != "true":
        return {"posted": False, "reason": "disabled"}
    if not telegram_configured():
        return {"posted": False, "reason": "no_telegram_bot"}
    if _days_since(state.get("last_quest_post")) < interval_days:
        return {"posted": False, "reason": "interval"}
    ok = send_telegram(QUEST_MESSAGE)
    if ok:
        state["last_quest_post"] = now_iso()
    return {"posted": ok}


def _nudge_pr_if_due(state: dict[str, Any], interval_days: float) -> dict[str, Any]:
    if os.environ.get("LISTING_PR_NUDGE_ENABLED", "true").lower() != "true":
        return {"nudged": False, "reason": "disabled"}
    if _days_since(state.get("last_pr_nudge")) < interval_days:
        return {"nudged": False, "reason": "interval"}
    pr = check_ton_assets_pr()
    if pr.get("state") != "OPEN":
        return {"nudged": False, "reason": "pr_not_open", "pr": pr}
    result = nudge_ton_assets_pr_if_stale()
    if result.get("nudged"):
        state["last_pr_nudge"] = now_iso()
    return result


def _build_summary(run: dict[str, Any]) -> str:
    ds = run["checks"]["dexscreener_pair"]
    ton = run["checks"]["tonapi"]
    rates = run["checks"]["tonapi_rates"]
    gates = run["checks"]["tonapi_price_gates"]
    pr = run["checks"]["ton_assets_pr"]
    elig = run["checks"]["eligibility"]
    lines = [
        "PLX listing automation",
        f"DexScreener: {'indexed' if ds.get('ok') else 'missing'} · LP ${ds.get('liquidity_usd', 0):.0f} · pool ~{gates.get('pool_ton_quote', 0):.1f} TON",
        f"TonAPI: {ton.get('verification') or 'no_key'} · holders {ton.get('holders')}",
        f"TonAPI rates USD: {rates.get('usd', 0)} · Tonkeeper USD: {'OK' if gates.get('tonapi_price_ready') else 'BLOCKED'}",
        f"Tonkeeper gates: holders {gates.get('holders')}/{gates.get('min_holders')} · TON {gates.get('pool_ton_quote', 0):.1f}/{gates.get('min_ton_reserve')}",
        f"ton-assets PR: {pr.get('state')}",
        f"CoinGecko gate: {'ready' if elig.get('coingecko_ready') else 'need $' + str(elig.get('coingecko_min_usd'))}",
        f"DYOR indexed: {run['checks']['dyor'].get('indexed')}",
        f"Quest posted: {run['actions']['quest'].get('posted')}",
        "Runbook: docs/TONKEEPER-USD-PRICE-RUNBOOK.md",
        f"Details: {TOKEN_PAGE}",
    ]
    return "\n".join(lines)


def _alert_tonkeeper_usd_blocked(run: dict[str, Any]) -> dict[str, Any]:
    """Telegram alert when whitelist but TonAPI rates still zero."""
    if os.environ.get("LISTING_TONAPI_RATES_ALERT", "true").lower() != "true":
        return {"sent": False, "reason": "disabled"}
    if not telegram_configured():
        return {"sent": False, "reason": "no_telegram_bot"}
    ton = run["checks"]["tonapi"]
    rates = run["checks"]["tonapi_rates"]
    gates = run["checks"]["tonapi_price_gates"]
    if ton.get("verification") != "whitelist":
        return {"sent": False, "reason": "not_whitelist"}
    if rates.get("price_ready"):
        return {"sent": False, "reason": "rates_ok"}
    msg = (
        "PLX Tonkeeper USD blocked\n\n"
        f"TonAPI verification: whitelist\n"
        f"Rates USD: {rates.get('usd', 0)} (need > 0)\n"
        f"Holders: {gates.get('holders')}/{gates.get('min_holders')}\n"
        f"Pool TON: {gates.get('pool_ton_quote', 0):.1f}/{gates.get('min_ton_reserve')}\n\n"
        "Deepen LP (plx-lp) + grow holders — see docs/TONKEEPER-USD-PRICE-RUNBOOK.md"
    )
    ok = send_telegram(msg)
    return {"sent": ok}


def main() -> int:
    if not _enabled():
        print(json.dumps({"ok": True, "skipped": "LISTING_AUTOMATION_ENABLED false"}))
        return 0

    state = _load_state()
    quest_days = float(os.environ.get("LISTING_QUEST_INTERVAL_DAYS", "7"))
    nudge_days = float(os.environ.get("LISTING_PR_NUDGE_INTERVAL_DAYS", "14"))

    ds = check_dexscreener_pair()
    stonfi = check_stonfi_pool_ton()
    pool_ton = ds.get("pool_ton_quote")
    if pool_ton is None and stonfi.get("ton_human") is not None:
        pool_ton = stonfi.get("ton_human")
    gates = eligibility_gates(float(ds.get("liquidity_usd") or 0))
    ton = check_tonapi_jetton()
    rates = check_tonapi_rates()
    tonapi_gates = tonapi_price_gates(
        holders=ton.get("holders") if isinstance(ton.get("holders"), int) else None,
        pool_ton_quote=pool_ton,
        usd_price=float(rates.get("usd") or 0),
    )

    run: dict[str, Any] = {
        "at": now_iso(),
        "checks": {
            "dexscreener_pair": ds,
            "stonfi_pool": stonfi,
            "dexscreener_orders": check_dexscreener_orders(),
            "tonapi": ton,
            "tonapi_rates": rates,
            "tonapi_price_gates": tonapi_gates,
            "dyor": check_dyor_indexed(),
            "coingecko": check_coingecko_listed(),
            "ton_assets_pr": check_ton_assets_pr(),
            "eligibility": gates,
        },
        "actions": {},
    }

    run["actions"]["quest"] = _post_quest_if_due(state, quest_days)
    run["actions"]["pr_nudge"] = _nudge_pr_if_due(state, nudge_days)
    run["actions"]["branding_swap"] = _run_branding_swap()

    run["platform_notes"] = {
        "tonscan_labels": "no_api — automation monitors only",
        "tonviewer_labels": "no_api — automation monitors only",
        "tapps_center": "blocked_until_mini_app_demo",
        "coinmarketcap": "blocked_until_volume_gate"
        if not gates.get("cmc_ready")
        else "ready_for_manual_or_future_form_bot",
        "coingecko": "blocked_until_lp_gate"
        if not gates.get("coingecko_ready")
        else "eligible_not_auto_submitted",
    }

    summary = _build_summary(run)

    summary_hours = float(os.environ.get("LISTING_SUMMARY_INTERVAL_HOURS", "24"))
    if _days_since(state.get("last_summary_sent")) >= summary_hours / 24:
        run["actions"]["telegram_summary"] = send_telegram(summary)
        if run["actions"]["telegram_summary"]:
            state["last_summary_sent"] = now_iso()
    else:
        run["actions"]["telegram_summary"] = "skipped_summary_interval"
    run["actions"]["tonkeeper_usd_alert"] = _alert_tonkeeper_usd_blocked(run)

    marketing_days = float(os.environ.get("LISTING_MARKETING_INTERVAL_DAYS", "7"))
    if (
        os.environ.get("TELEGRAM_MARKETING_ENABLED", "").lower() == "true"
        and _days_since(state.get("last_marketing_run")) >= marketing_days
    ):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "plx-telegram-marketing.py")],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            env=os.environ.copy(),
            timeout=120,
            check=False,
        )
        try:
            run["actions"]["telegram_marketing"] = json.loads(proc.stdout or "{}")
        except json.JSONDecodeError:
            run["actions"]["telegram_marketing"] = {
                "raw": (proc.stdout or proc.stderr)[:500]
            }
        state["last_marketing_run"] = now_iso()
    elif os.environ.get("TELEGRAM_MARKETING_ENABLED", "").lower() == "true":
        run["actions"]["telegram_marketing"] = "skipped_marketing_interval"
    else:
        run["actions"]["telegram_marketing"] = "skipped_disabled"

    state["runs"] = (state.get("runs") or [])[-49:] + [run]
    state["last_run"] = run["at"]
    _save_state(state)
    _append_log(run)

    print(json.dumps({"ok": True, "run": run}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
