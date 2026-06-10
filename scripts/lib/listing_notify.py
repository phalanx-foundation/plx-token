"""Telegram notifications for listing automation."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

DEFAULT_OPS_CHAT = "930979766"


def _chat_ids() -> list[str]:
    ids: list[str] = []
    for key in ("LISTING_QUEST_CHAT_ID", "TELEGRAM_PUBLIC_CHAT_ID", "TELEGRAM_OPS_CHAT_ID"):
        val = os.environ.get(key, "").strip()
        if val and val not in ids:
            ids.append(val)
    if not ids:
        fallback = os.environ.get("TELEGRAM_OPS_CHAT_ID", DEFAULT_OPS_CHAT).strip()
        if fallback:
            ids.append(fallback)
    return ids


def telegram_configured() -> bool:
    return bool(os.environ.get("TOKEN_TELEGRAM_BOT", "").strip())


def send_telegram(text: str, *, chat_id: str | None = None) -> bool:
    token = os.environ.get("TOKEN_TELEGRAM_BOT", "").strip()
    if not token:
        return False
    targets = [chat_id] if chat_id else _chat_ids()
    ok = False
    for cid in targets:
        if not cid:
            continue
        body = json.dumps({"chat_id": cid, "text": text[:4096]}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as res:
                ok = res.status == 200 or ok
        except (urllib.error.URLError, TimeoutError):
            continue
    return ok
