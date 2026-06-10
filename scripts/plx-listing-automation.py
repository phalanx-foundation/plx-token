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
    check_tonapi_jetton,
    check_ton_assets_pr,
    eligibility_gates,
    now_iso,
    nudge_ton_assets_pr_if_stale,
)
from lib.listing_notify import send_telegram, telegram_configured  # noqa: E402
from lib.listing_pack import QUEST_MESSAGE, TOKEN_PAGE  # noqa: E402

STATE_FILE = Path(os.environ.get("LISTING_STATE_FILE", ROOT / "data" / "listing-automation-state.json"))
LOG_FILE = Path(os.environ.get("LISTING_LOG_FILE", ROOT / "data" / "listing-automation-log.json"))


def _enabled() -> bool:
    return os.environ.get("LISTING_AUTOMATION_ENABLED", "").lower() == "true"


def _load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {"runs": [], "last_quest_post": None, "last_pr_nudge": None}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {"runs": [], "last_quest_post": None, "last_pr_nudge": None}


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
    pr = run["checks"]["ton_assets_pr"]
    gates = run["checks"]["eligibility"]
    lines = [
        "PLX listing automation",
        f"DexScreener: {'indexed' if ds.get('ok') else 'missing'} · LP ${ds.get('liquidity_usd', 0):.0f}",
        f"TonAPI: {ton.get('verification') or 'no_key'} · holders {ton.get('holders')}",
        f"ton-assets PR: {pr.get('state')}",
        f"CoinGecko gate: {'ready' if gates.get('coingecko_ready') else 'need $' + str(gates.get('coingecko_min_usd'))}",
        f"DYOR indexed: {run['checks']['dyor'].get('indexed')}",
        f"Quest posted: {run['actions']['quest'].get('posted')}",
        f"Details: {TOKEN_PAGE}",
    ]
    return "\n".join(lines)


def main() -> int:
    if not _enabled():
        print(json.dumps({"ok": True, "skipped": "LISTING_AUTOMATION_ENABLED false"}))
        return 0

    state = _load_state()
    quest_days = float(os.environ.get("LISTING_QUEST_INTERVAL_DAYS", "7"))
    nudge_days = float(os.environ.get("LISTING_PR_NUDGE_INTERVAL_DAYS", "14"))

    ds = check_dexscreener_pair()
    gates = eligibility_gates(float(ds.get("liquidity_usd") or 0))

    run: dict[str, Any] = {
        "at": now_iso(),
        "checks": {
            "dexscreener_pair": ds,
            "dexscreener_orders": check_dexscreener_orders(),
            "tonapi": check_tonapi_jetton(),
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
        "coinmarketcap": "blocked_until_volume_gate" if not gates.get("cmc_ready") else "ready_for_manual_or_future_form_bot",
        "coingecko": "blocked_until_lp_gate" if not gates.get("coingecko_ready") else "eligible_not_auto_submitted",
    }

    summary = _build_summary(run)
    run["actions"]["telegram_summary"] = send_telegram(summary)

    state["runs"] = (state.get("runs") or [])[-49:] + [run]
    state["last_run"] = run["at"]
    _save_state(state)
    _append_log(run)

    print(json.dumps({"ok": True, "run": run}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
