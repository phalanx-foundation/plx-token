#!/usr/bin/env python3
"""
Automated fundraising pipeline — GitHub issues + Telegram (like ton-assets PR workflow).

Cron: 0 9 * * 1 cd ~/projects/plx-acton && python3 scripts/plx-fundraising-automation.py

Requires: FUNDRAISING_AUTOMATION_ENABLED=true, gh auth, TOKEN_TELEGRAM_BOT (optional)
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

from lib.dotenv_load import load_project_dotenv
from lib.listing_notify import send_telegram, telegram_configured
from lib.listing_pack import (
    DESCRIPTION,
    GITHUB,
    PLX_MINTER,
    STONFI_POOL_URL,
    TOKEN_PAGE,
)

load_project_dotenv()

STATE_FILE = Path(
    os.environ.get(
        "FUNDRAISING_STATE_FILE", ROOT / "data" / "fundraising-automation-state.json"
    )
)
REPO = os.environ.get("FUNDRAISING_GITHUB_REPO", "phalanx-foundation/plx-token")

TRACKS: list[dict[str, Any]] = [
    {
        "id": "ton_ecosystem_grant",
        "title": "[Funding] TON ecosystem grant — Phalanx Toolkit + PLX",
        "apply_url": "https://ton.org/en/ton-grants",
        "labels": ["funding", "grants"],
        "body": f"""## Program
TON Foundation / ecosystem grants (TON-native jetton + open toolkit).
Model 2026: Contender -> Champion, milestone-based. 5 verticals (AI, Simplified DeFi,
Telegram In-App Economy, Payments, GameFi).

## Project
- **Site:** {TOKEN_PAGE}
- **Contracts:** {GITHUB}
- **PLX minter:** `{PLX_MINTER}`
- **Ston.fi pool:** {STONFI_POOL_URL}
- **Tonkeeper ton-assets:** PR https://github.com/tonkeeper/ton-assets/pull/5540

## Vertical
Simplified DeFi (primary) + Telegram In-App Economy (secondary) + open-source public goods.

## Pitch
{DESCRIPTION}

## Milestones (grant, milestone-based)
1. Deploy grant TON + matching PLX to Ston.fi pool -> on-chain (M1 LP bootstrap)
2. Deploy TokenStaking + TokenGovernance to mainnet (M3)
3. Third-party audit (M4)
4. Toolkit E2E across 6 Jetton templates (M5)

## Apply
https://ton.org/en/ton-grants (portal ecosystem TON; NOT builders.ton.org — deprecated).

## Agent
Auto-opened by `scripts/plx-fundraising-automation.py`
""",
    },
    {
        "id": "stonfi_grant",
        "title": "[Funding] STON.fi DEX Grant — SDK integration (Phalanx)",
        "apply_url": "https://ston.fi/grant-program",
        "labels": ["funding", "grants"],
        "body": f"""## Program
STON.fi DEX Grant — up to $10K USDT, evergreen. Requires STON.fi SDK/widget integration
(already live in production).

## Integration proof
- LP provisioning: `toolkit-staging/web/lib/stonfi-liquidity.ts` (StonApiClient + dexFactory)
- Swap: `toolkit-staging/web/lib/stonfi-swap-sell.ts`
- UI: `add-liquidity-panel.tsx`, `plx86-swap-sheet.tsx`
- Pool: {STONFI_POOL_URL}

## Pitch
No-code Jetton deployer that routes every deployed token through STON.fi SDK for
liquidity + swap -> every deploy = new pool + volume for STON.fi (ecosystem multiplier).

## Apply
https://ston.fi/grant-program

## Agent
Auto-opened by `scripts/plx-fundraising-automation.py`
""",
    },
    {
        "id": "gitcoin_oss",
        "title": "[Funding] Gitcoin Grants — plx-token open source",
        "apply_url": "https://grants.gitcoin.co/",
        "labels": ["funding", "grants"],
        "body": f"""## Program
Gitcoin OSS / dependency round.

## Repo
{GITHUB} (public, Acton tests, JettonMinter Tolk)

## Use of funds
Infra + LP bootstrap TON (transparent treasury), not personal salary.

## Apply
Register project when round opens: https://grants.gitcoin.co/

Auto-tracked by fundraising automation.
""",
    },
    {
        "id": "animoca_intro",
        "title": "[Funding] Animoca Brands — TON toolkit + Mini App intro",
        "apply_url": "https://www.animocabrands.com/",
        "labels": ["funding", "vc"],
        "body": f"""## Angle
Phalanx Toolkit on TON — audited jetton deploy funnel; PLX as reference token with live Ston.fi LP.

## Links
- {TOKEN_PAGE}
- {GITHUB}

## Ask
Strategic intro / seed conversation (product equity), **not** PLX market sale.

## LP context
Thin LP (~$34) — seeking ecosystem partner or grant path before large LP.

Auto-opened by fundraising automation.
""",
    },
    {
        "id": "microsoft_founders_hub",
        "title": "[Funding] Microsoft for Startups Founders Hub",
        "apply_url": "https://foundershub.startup.microsoft.com/",
        "labels": ["funding", "ai-grants"],
        "body": """## Program
Azure credits, GitHub Enterprise, OpenAI API credits for PLX86 / toolkit API.

## Entity
Phalanx Foundation — https://plx.foundation

## Use
Reduce cloud spend → redirect savings to TON LP bootstrap.

## Apply
https://foundershub.startup.microsoft.com/

Auto-tracked by fundraising automation.
""",
    },
    {
        "id": "google_cloud_startup",
        "title": "[Funding] Google for Startups Cloud Program",
        "apply_url": "https://cloud.google.com/startup",
        "labels": ["funding", "ai-grants"],
        "body": """## Program
GCP credits + GPU trial for PLX86 inference (self-host vs edge-only).

## Site
https://plx.foundation

## Apply
https://cloud.google.com/startup

Auto-tracked by fundraising automation.
""",
    },
    {
        "id": "kickstarter_toolkit",
        "title": "[Funding] Kickstarter / Indiegogo — Phalanx Toolkit (product, not token)",
        "apply_url": "https://www.kickstarter.com/start",
        "labels": ["funding", "crowdfunding"],
        "body": f"""## Campaign (draft)
**Product:** Lifetime / early-builder Phalanx Toolkit tier on TON.

## NOT selling
PLX as investment — utility software only.

## Demo required
2–3 min video: `/build` mainnet happy path.

## Links
- {TOKEN_PAGE}
- Pool (utility context): {STONFI_POOL_URL}

## Proceeds
Net → treasury → TON for LP (see TRANSPARENCY.md).

Auto-tracked by fundraising automation.
""",
    },
]


def _enabled() -> bool:
    return os.environ.get("FUNDRAISING_AUTOMATION_ENABLED", "").lower() == "true"


def _load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {"issues": {}, "last_run": None}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {"issues": {}, "last_run": None}


def _save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def _gh_issue_exists(title: str) -> str | None:
    proc = subprocess.run(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            REPO,
            "--state",
            "all",
            "--search",
            title[:80],
            "--json",
            "url,title",
            "--limit",
            "5",
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if proc.returncode != 0:
        return None
    try:
        items = json.loads(proc.stdout or "[]")
    except json.JSONDecodeError:
        return None
    for item in items:
        if isinstance(item, dict) and item.get("title") == title:
            return item.get("url")
    return None


def _create_issue(track: dict[str, Any]) -> dict[str, Any]:
    existing = _gh_issue_exists(track["title"])
    if existing:
        return {"created": False, "url": existing, "reason": "exists"}
    label_args: list[str] = []
    for lab in track.get("labels", []):
        label_args.extend(["--label", lab])
    proc = subprocess.run(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            REPO,
            "--title",
            track["title"],
            "--body",
            track["body"],
            *label_args,
        ],
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )
    if proc.returncode != 0:
        return {
            "created": False,
            "error": (proc.stderr or proc.stdout or "gh failed")[:400],
        }
    url = proc.stdout.strip()
    return {"created": True, "url": url}


def main() -> int:
    if not _enabled():
        print(
            json.dumps({"ok": True, "skipped": "FUNDRAISING_AUTOMATION_ENABLED false"})
        )
        return 0

    state = _load_state()
    run: dict[str, Any] = {"at": datetime.now(timezone.utc).isoformat(), "tracks": {}}

    for track in TRACKS:
        result = _create_issue(track)
        result["apply_url"] = track["apply_url"]
        run["tracks"][track["id"]] = result
        if result.get("url"):
            state["issues"][track["id"]] = result["url"]

    lines = ["Phalanx fundraising automation"]
    for tid, res in run["tracks"].items():
        flag = "NEW" if res.get("created") else "track"
        lines.append(f"{tid}: {flag} {res.get('url') or res.get('error', '?')}")
        lines.append(f"  apply: {res.get('apply_url')}")

    summary = "\n".join(lines)
    run["telegram"] = send_telegram(summary) if telegram_configured() else False

    state["last_run"] = run["at"]
    _save_state(state)

    # Run the dedicated grants/deadline tracker in the same cron pass so
    # application status + deadline alerts stay in sync with GitHub tickets.
    grants_result: dict[str, Any] = {"skipped": "GRANTS_TRACKER_ENABLED false"}
    if os.environ.get("GRANTS_TRACKER_ENABLED", "").lower() == "true":
        try:
            import importlib.util

            grants_path = ROOT / "scripts" / "grants-tracker.py"
            spec = importlib.util.spec_from_file_location("grants_tracker", grants_path)
            if spec is None or spec.loader is None:
                raise ImportError("cannot load grants-tracker.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            grants_result = module.main()
        except Exception as exc:  # noqa: BLE001
            grants_result = {"error": f"{type(exc).__name__}: {exc}"}

    print(json.dumps({"ok": True, "run": run, "grants_tracker": grants_result}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
