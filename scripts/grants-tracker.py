#!/usr/bin/env python3
"""Grants / investor tracker — deadline alert + submission pack generation.

A separate module from plx-fundraising-automation.py (which creates GitHub
funding issue tickets). This one tracks *application statuses and deadlines*
per grant/platform and, on a configurable interval, posts Telegram alerts
for anything near its deadline.

Because almost every platform below is a web form / Telegram bot with no
public API, this does NOT auto-submit. Its job is:
  1. Hold a register of targets (from docs/GRANTS-INVESTOR-INDEX.md).
  2. Alert (Telegram) when a deadline is within `DEADLINE_WINDOW_DAYS`.
  3. Generate a copy-paste submission pack per target for the human.
  4. Push status transitions (draft / submitted / rejected / awarded).

Cron (Ubuntu acton server):
    0 9 * * * cd ~/projects/plx-acton && python3 scripts/grants-tracker.py >> logs/grants-tracker.log 2>&1

Env:
    GRANTS_TRACKER_ENABLED=true
    TOKEN_TELEGRAM_BOT=... (for alerts; optional)
    TELEGRAM_OPS_CHAT_ID=... (default 930979766)
    GRANTS_STATE_FILE=...    (default <repo>/data/grants-state.json)
"""

from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.dotenv_load import load_project_dotenv  # noqa: E402
from lib.listing_notify import send_telegram, telegram_configured  # noqa: E402

load_project_dotenv()

STATE_FILE = Path(
    os.environ.get("GRANTS_STATE_FILE", ROOT / "data" / "grants-state.json")
)
DEADLINE_WINDOW_DAYS = int(os.environ.get("GRANTS_DEADLINE_WINDOW_DAYS", "7"))
OUTPUT_DIR = ROOT / "data" / "grant-packs"

# Canonical target register. `deadline` is ISO date or None (= evergreen).
# `tier` mirrors docs/GRANTS-INVESTOR-INDEX.md.
TARGETS: list[dict[str, Any]] = [
    {
        "id": "stonfi_grant",
        "name": "STON.fi DEX Grant",
        "tier": 1,
        "amount": "up to $10K USDT",
        "apply_url": "https://ston.fi/grant-program",
        "status": "draft",
        "deadline": None,
        "notes": "SDK integration already live; evergreen.",
        "pack": "toolkit-staging/docs/STONFI-GRANT-APPLICATION.md",
    },
    {
        "id": "microsoft_founders_hub",
        "name": "Microsoft Founders Hub",
        "tier": 1,
        "amount": "~$150K Azure credits",
        "apply_url": "https://foundershub.startup.microsoft.com/",
        "status": "draft",
        "deadline": None,
        "notes": "Rolling; no traction gate.",
        "pack": "docs/FUNDRAISING-AND-LP-OPTIONS.md",
    },
    {
        "id": "google_cloud_startup",
        "name": "Google Cloud Startup",
        "tier": 1,
        "amount": "~$100K GCP credits",
        "apply_url": "https://cloud.google.com/startup",
        "status": "draft",
        "deadline": None,
        "notes": "Rolling; no traction gate.",
        "pack": "docs/FUNDRAISING-AND-LP-OPTIONS.md",
    },
    {
        "id": "gitcoin_oss",
        "name": "Gitcoin OSS Round",
        "tier": 1,
        "amount": "ETH matching pool",
        "apply_url": "https://grants.gitcoin.co/",
        "status": "draft",
        "deadline": None,
        "notes": "Open-source repo; per-round.",
        "pack": "scripts/plx-fundraising-automation.py",
    },
    {
        "id": "ton_foundation_champion",
        "name": "TON Foundation Champion Grants",
        "tier": 2,
        "amount": "milestone-based",
        "apply_url": "https://ton.org/en/ton-grants",
        "status": "draft",
        "deadline": None,
        "notes": "Contender -> Champion; 5 verticals.",
        "pack": "docs/TON-GRANT-APPLICATION.md",
    },
    {
        "id": "ton_society_bounties",
        "name": "TON Society Grants & Bounties",
        "tier": 2,
        "amount": "per-bounty",
        "apply_url": "https://github.com/ton-society/grants-and-bounties",
        "status": "paused",
        "deadline": None,
        "notes": "PAUSED (review); monitor.",
        "pack": "docs/GRANTS-INVESTOR-INDEX.md",
    },
    {
        "id": "ton_web3_grants",
        "name": "Telegram Web3 Grants (Type A/B)",
        "tier": 2,
        "amount": "up to $10K TON",
        "apply_url": "https://ton.org/en/ton-grants",
        "status": "draft",
        "deadline": None,
        "notes": "Type A/B suitable for live TON project.",
        "pack": "docs/TON-GRANT-APPLICATION.md",
    },
    {
        "id": "toncoin_fund",
        "name": "TONcoin.Fund",
        "tier": 3,
        "amount": "$250M syndicate (equity/token)",
        "apply_url": "https://www.toncoin.fund/",
        "status": "draft",
        "deadline": None,
        "notes": "VC, needs equity; not a grant.",
        "pack": "docs/GRANTS-INVESTOR-INDEX.md",
    },
    {
        "id": "open_builders",
        "name": "Open Builders (Tonstarter)",
        "tier": 3,
        "amount": "incubation + fundraising",
        "apply_url": "https://forms.tonstarter.com/build",
        "status": "draft",
        "deadline": None,
        "notes": "4-page form; needs deck + tokenomics.",
        "pack": "docs/GRANTS-INVESTOR-INDEX.md",
    },
]


def _enabled() -> bool:
    return os.environ.get("GRANTS_TRACKER_ENABLED", "").lower() == "true"


def _load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {"targets": {}, "last_run": None}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {"targets": {}, "last_run": None}


def _save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def _deadline_days(target: dict[str, Any]) -> int | None:
    """Days until deadline (or None for evergreen/no deadline). Negative = overdue."""
    raw = target.get("deadline")
    if not raw or raw in ("", "evergreen", "None", "rolling"):
        return None
    try:
        dl = date.fromisoformat(str(raw)[:10])
    except ValueError:
        return None
    return (dl - date.today()).days


def _needs_alert(target: dict[str, Any]) -> bool:
    days = _deadline_days(target)
    if days is None:
        return False
    status = (target.get("status") or "draft").lower()
    # Alert only for actionable, unfinished targets near (or past) deadline.
    if status in ("awarded", "rejected"):
        return False
    return days <= DEADLINE_WINDOW_DAYS


def _render_pack(target: dict[str, Any]) -> str:
    """Build a copy-paste submission pack markdown for a target."""
    days = _deadline_days(target)
    deadline_str = (
        target.get("deadline")
        if days is None
        else f"{target.get('deadline')} ({days}d remaining)"
    )
    lines = [
        f"# Grant submission pack — {target['name']}",
        "",
        f"- Amount: {target.get('amount')}",
        f"- Apply: {target.get('apply_url')}",
        f"- Deadline: {deadline_str}",
        f"- Status: {target.get('status')}",
        f"- Notes: {target.get('notes')}",
        "",
        "## Copy this into the platform form",
        "",
        f"Project: Phalanx (PLX)",
        f"Site: https://plx.foundation",
        f"GitHub: https://github.com/phalanx-foundation/plx-token",
        f"Minter: `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`",
        f"Ston.fi pool: `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq`",
        "",
        "### Pitch",
        "No-code audited Jetton deployer & launchpad on TON. Deploy a full-feature Token in 5 minutes "
        "from browser; on-chain vesting, staking, governance, anti-whale built-in. 22 MIT-licensed "
        "contracts, TEP-74/64, Acton+Tolk. Self-funded, no VC, no IDO.",
        "",
        "### Milestones",
        "1. LP bootstrap from grant funds -> on-chain (Ston.fi PLX/TON)",
        "2. Deploy TokenStaking + TokenGovernance to mainnet",
        "3. Third-party audit of new contracts",
        "4. Toolkit E2E across 6 Jetton templates",
        "",
        "### Traction (honest)",
        "Live mainnet, ~$34 LP, 9 holders, 22 contracts, 72 passing Acton tests.",
        "",
        '> Drafted by scripts/grants-tracker.py. Verify against platform criteria before submit.',
    ]
    return "\n".join(lines)


def _write_pack(target: dict[str, Any]) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{target['id']}.md"
    path.write_text(_render_pack(target), encoding="utf-8")
    return path


def _status_line(target: dict[str, Any]) -> str:
    days = _deadline_days(target)
    dl = "evergreen" if days is None else (f"{days}d" if days >= 0 else f"OVERDUE {-days}d")
    return f"- {target['id']}: status={target.get('status')} | {target.get('amount')} | deadline={dl}"


def main() -> int:
    if not _enabled():
        print(json.dumps({"ok": True, "skipped": "GRANTS_TRACKER_ENABLED false"}))
        return 0

    state = _load_state()
    state.setdefault("targets", {})
    # Merge persisted status into register so manual transitions survive edits.
    for tgt in TARGETS:
        stored = state["targets"].get(tgt["id"])
        if stored and isinstance(stored, dict):
            tgt["status"] = stored.get("status", tgt["status"])
            tgt["deadline"] = stored.get("deadline", tgt["deadline"])

    alerts: list[str] = []
    packs: list[str] = []
    for tgt in TARGETS:
        packs.append(_write_pack(tgt).name)
        if _needs_alert(tgt):
            days = _deadline_days(tgt)
            msg = (
                f"GRANT ALERT: {tgt['name']} deadline within {DEADLINE_WINDOW_DAYS}d"
                if days is None
                else f"GRANT ALERT: {tgt['name']} -> {tgt['deadline']} ({days}d remaining)"
            )
            alerts.append(msg)

    # Persist current targets + status for next run.
    for tgt in TARGETS:
        state["targets"][tgt["id"]] = {"status": tgt["status"], "deadline": tgt["deadline"]}

    if alerts:
        body = "\n".join(alerts)
        sent = send_telegram(body) if telegram_configured() else False
    else:
        sent = False

    state["last_run"] = datetime.now(timezone.utc).isoformat()
    _save_state(state)

    print(
        json.dumps(
            {
                "ok": True,
                "targets": len(TARGETS),
                "packs_written": len(packs),
                "alerts": alerts,
                "telegram_sent": sent,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
