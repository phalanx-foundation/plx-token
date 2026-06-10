#!/usr/bin/env python3
"""
Telegram marketing for PLX — bot profile + broadcast announcements.

Run after TOKEN_TELEGRAM_BOT is in .env:
  TELEGRAM_MARKETING_ENABLED=true python scripts/plx-telegram-marketing.py

Optional: TELEGRAM_MARKETING_CHANNELS=-100xxx,@yourchannel (comma-separated)
Default: TELEGRAM_OPS_CHAT_ID or 930979766
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.dotenv_load import load_project_dotenv  # noqa: E402
from lib.listing_pack import (  # noqa: E402
    DEXSCREENER_PAIR_URL,
    PLX_MINTER,
    QUEST_MESSAGE,
    STONFI_POOL_URL,
    TOKEN_PAGE,
)

load_project_dotenv()

STATE_FILE = Path(os.environ.get("TELEGRAM_MARKETING_STATE", ROOT / "data" / "telegram-marketing-state.json"))

LAUNCH_MESSAGE = f"""🛡 Phalanx (PLX) — live on TON mainnet

PLX is the audited utility jetton behind Phalanx Toolkit: deploy jettons, pay with PLX (-50%), burn-on-receipt.

📊 Token page: {TOKEN_PAGE}
💱 Swap on Ston.fi: {STONFI_POOL_URL}
📈 Chart: {DEXSCREENER_PAIR_URL}
🔍 Minter: `{PLX_MINTER}`

Open-source contracts · 1B fixed supply · Ston.fi LP seeded.

Commands: /site /swap /price /quest

Not investment advice. Utility token for builders on TON.
"""


def _token() -> str:
    return (
        os.environ.get("TOKEN_TELEGRAM_BOT")
        or os.environ.get("TELEGRAM_BOT_TOKEN")
        or ""
    ).strip()


def _api(method: str, payload: dict[str, Any] | None = None, *, get: bool = False) -> dict[str, Any]:
    token = _token()
    if not token:
        return {"ok": False, "error": "no bot token"}
    if get:
        url = f"https://api.telegram.org/bot{token}/{method}"
        req = urllib.request.Request(url, method="GET")
    else:
        url = f"https://api.telegram.org/bot{token}/{method}"
        body = json.dumps(payload or {}).encode()
        req = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.loads(res.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except json.JSONDecodeError:
            return {"ok": False, "error": str(e)}


def _broadcast_targets() -> list[str]:
    raw = os.environ.get("TELEGRAM_MARKETING_CHANNELS", "").strip()
    if raw:
        return [x.strip() for x in raw.split(",") if x.strip()]
    ops = os.environ.get("TELEGRAM_OPS_CHAT_ID", "930979766").strip()
    return [ops] if ops else []


def _load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {}


def _save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def setup_bot_profile() -> dict[str, Any]:
    return {
        "setMyDescription": _api(
            "setMyDescription",
            {
                "description": (
                    "Phalanx (PLX) on TON mainnet — utility jetton for Phalanx Toolkit. "
                    "Swap on Ston.fi, explore at plx.foundation/plx-token. Not financial advice."
                )[:512],
            },
        ),
        "setMyShortDescription": _api(
            "setMyShortDescription",
            {"short_description": "PLX utility jetton · Phalanx Toolkit on TON mainnet"[:120]},
        ),
        "setMyCommands": _api(
            "setMyCommands",
            {
                "commands": [
                    {"command": "start", "description": "Welcome + mainnet links"},
                    {"command": "site", "description": "plx.foundation/plx-token"},
                    {"command": "swap", "description": "Ston.fi PLX/TON pool"},
                    {"command": "price", "description": "DexScreener chart link"},
                    {"command": "quest", "description": "Builder swap quest rules"},
                ],
            },
        ),
    }


def send_message(chat_id: str, text: str) -> dict[str, Any]:
    return _api(
        "sendMessage",
        {
            "chat_id": chat_id,
            "text": text[:4096],
            "disable_web_page_preview": False,
        },
    )


def run_broadcast(force: bool = False) -> dict[str, Any]:
    state = _load_state()
    if state.get("launch_sent") and not force:
        return {"skipped": "launch_already_sent", "use": "TELEGRAM_MARKETING_FORCE=true"}

    results: dict[str, Any] = {"targets": {}, "profile": setup_bot_profile()}
    for chat in _broadcast_targets():
        launch = send_message(chat, LAUNCH_MESSAGE)
        quest = send_message(chat, QUEST_MESSAGE)
        results["targets"][chat] = {"launch": launch.get("ok"), "quest": quest.get("ok"), "errors": []}
        if not launch.get("ok"):
            results["targets"][chat]["errors"].append(launch.get("description", launch))
        if not quest.get("ok"):
            results["targets"][chat]["errors"].append(quest.get("description", quest))

    if any(t.get("launch") for t in results["targets"].values()):
        state["launch_sent"] = datetime.now(timezone.utc).isoformat()
        state["last_broadcast"] = state["launch_sent"]
        _save_state(state)

    return results


def main() -> int:
    if os.environ.get("TELEGRAM_MARKETING_ENABLED", "").lower() != "true":
        print(json.dumps({"ok": True, "skipped": "TELEGRAM_MARKETING_ENABLED false"}))
        return 0
    if not _token():
        print(json.dumps({"ok": False, "error": "TOKEN_TELEGRAM_BOT missing in .env"}))
        return 1

    force = os.environ.get("TELEGRAM_MARKETING_FORCE", "").lower() == "true"
    result = run_broadcast(force=force)
    print(json.dumps({"ok": True, "result": result}, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
