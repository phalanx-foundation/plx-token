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

TELEGRAM_CHANNEL = "https://t.me/phalanxfoundation"
TELEGRAM_BOT = "https://t.me/phalanxfoundationbot"

CHANNEL_WELCOME = f"""Welcome to the official Phalanx Foundation channel

PLX is live on TON mainnet — utility jetton for Phalanx Toolkit (deploy jettons, pay with PLX -50%, burn-on-receipt).

Token page: {TOKEN_PAGE}
Ston.fi pool: {STONFI_POOL_URL}
Chart: {DEXSCREENER_PAIR_URL}
Minter: `{PLX_MINTER}`

Bot: {TELEGRAM_BOT} — send /start for commands (/site /swap /price /quest)

Builders: join the swap quest, follow listing updates, transparent treasury policy.

Not investment advice.
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
                    f"Channel: {TELEGRAM_CHANNEL} · Swap on Ston.fi · plx.foundation/plx-token. "
                    "Not financial advice."
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


def pin_message(chat_id: str, message_id: int) -> dict[str, Any]:
    return _api("pinChatMessage", {"chat_id": chat_id, "message_id": message_id})


def setup_webhook() -> dict[str, Any]:
    secret = os.environ.get("TELEGRAM_WEBHOOK_SECRET", "").strip()
    if not secret:
        return {"ok": False, "skipped": "TELEGRAM_WEBHOOK_SECRET missing"}
    base = os.environ.get("PUBLIC_API_URL", "https://api.plx.foundation").rstrip("/")
    url = f"{base}/telegram/webhook?secret={urllib.parse.quote(secret, safe='')}"
    _api("deleteWebhook", {"drop_pending_updates": False})
    return _api(
        "setWebhook",
        {"url": url, "allowed_updates": ["message", "edited_message"]},
    )


def post_channel_welcome(chat_id: str, *, force: bool = False) -> dict[str, Any]:
    state = _load_state()
    key = f"channel_welcome_{chat_id}"
    if state.get(key) and not force:
        return {"skipped": "channel_welcome_already_sent", "chat": chat_id}

    sent = send_message(chat_id, CHANNEL_WELCOME)
    result: dict[str, Any] = {"chat": chat_id, "send": sent.get("ok"), "pinned": False}
    if not sent.get("ok"):
        result["error"] = sent.get("description", sent)
        return result

    msg_id = (sent.get("result") or {}).get("message_id")
    if msg_id:
        pin = pin_message(chat_id, int(msg_id))
        result["pinned"] = pin.get("ok", False)
        if not pin.get("ok"):
            result["pin_error"] = pin.get("description", pin)

    state[key] = datetime.now(timezone.utc).isoformat()
    _save_state(state)
    return result


def run_broadcast(force: bool = False) -> dict[str, Any]:
    state = _load_state()
    if state.get("launch_sent") and not force:
        return {"skipped": "launch_already_sent", "use": "TELEGRAM_MARKETING_FORCE=true"}

    results: dict[str, Any] = {
        "targets": {},
        "profile": setup_bot_profile(),
        "webhook": setup_webhook(),
        "channel_welcome": {},
    }
    for chat in _broadcast_targets():
        results["channel_welcome"][chat] = post_channel_welcome(chat, force=force)
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
