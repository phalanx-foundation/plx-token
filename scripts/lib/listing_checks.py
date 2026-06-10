"""Platform status probes for PLX listing automation."""

from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

from lib.listing_pack import (
    COINGECKO_MIN_LP_USD,
    CMC_MIN_LP_USD,
    DEXSCREENER_PAIR_URL,
    PLX_MINTER,
    STONFI_POOL,
    STONFI_POOL_URL,
    TON_ASSETS_PR,
    TON_ASSETS_REPO,
)


def _http_json(url: str, *, headers: dict[str, str] | None = None, method: str = "GET", body: bytes | None = None) -> dict[str, Any] | None:
    req = urllib.request.Request(
        url,
        data=body,
        headers={"User-Agent": "PLX-ListingAutomation/1.0", **(headers or {})},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as res:
            data = json.loads(res.read().decode())
            return data if isinstance(data, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def check_dexscreener_pair() -> dict[str, Any]:
    url = f"https://api.dexscreener.com/latest/dex/pairs/ton/{STONFI_POOL}"
    data = _http_json(url)
    pairs = data.get("pairs") if data else None
    pair = pairs[0] if isinstance(pairs, list) and pairs else None
    liq = float(pair.get("liquidity", {}).get("usd", 0) or 0) if pair else 0.0
    return {
        "ok": pair is not None,
        "liquidity_usd": liq,
        "url": DEXSCREENER_PAIR_URL,
        "price_usd": pair.get("priceUsd") if pair else None,
        "txns_24h": pair.get("txns", {}).get("h24") if pair else None,
    }


def check_dexscreener_orders() -> dict[str, Any]:
    url = f"https://api.dexscreener.com/orders/v1/ton/{PLX_MINTER}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "PLX-ListingAutomation/1.0"})
        with urllib.request.urlopen(req, timeout=30) as res:
            raw = res.read().decode()
            orders = json.loads(raw)
            return {"ok": True, "orders": orders if isinstance(orders, list) else []}
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return {"ok": False, "orders": []}


def check_tonapi_jetton() -> dict[str, Any]:
    key = os.environ.get("TONAPI_KEY", os.environ.get("CONSOLE_TOKEN", "")).strip()
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    data = _http_json(f"https://tonapi.io/v2/jettons/{PLX_MINTER}", headers=headers)
    if not data:
        return {"ok": False, "error": "tonapi_unreachable_or_no_key"}
    return {
        "ok": True,
        "verification": data.get("verification"),
        "holders": data.get("holders_count"),
        "symbol": (data.get("metadata") or {}).get("symbol"),
    }


def check_dyor_indexed() -> dict[str, Any]:
    body = json.dumps({"address": [PLX_MINTER], "limit": 1, "excludeScam": False}).encode()
    data = _http_json(
        "https://api.dyor.io/v1/jettons",
        method="POST",
        headers={"Content-Type": "application/json"},
        body=body,
    )
    jettons = data.get("jettons") if data else None
    found = isinstance(jettons, list) and len(jettons) > 0
    return {"ok": found, "indexed": found, "count": len(jettons or [])}


def check_coingecko_listed() -> dict[str, Any]:
    search = _http_json(f"https://api.coingecko.com/api/v3/search?query=PLX%20Phalanx")
    coins = (search or {}).get("coins") if search else []
    match = None
    if isinstance(coins, list):
        for c in coins:
            if isinstance(c, dict) and "phalanx" in (c.get("name") or "").lower():
                match = c
                break
    return {"ok": match is not None, "coin": match}


def check_ton_assets_pr() -> dict[str, Any]:
    proc = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(TON_ASSETS_PR),
            "--repo",
            TON_ASSETS_REPO,
            "--json",
            "state,mergedAt,url,comments,updatedAt",
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if proc.returncode != 0:
        return {"ok": False, "error": (proc.stderr or proc.stdout or "gh failed")[:300]}
    try:
        pr = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"ok": False, "error": "invalid gh json"}
    comments = pr.get("comments") or []
    phalanx_comments = [
        c for c in comments if "phalanx" in (c.get("author", {}).get("login") or "").lower()
    ]
    return {
        "ok": True,
        "state": pr.get("state"),
        "merged": pr.get("mergedAt") is not None,
        "url": pr.get("url"),
        "phalanx_comment_count": len(phalanx_comments),
        "updated_at": pr.get("updatedAt"),
    }


def nudge_ton_assets_pr_if_stale(days: int = 14) -> dict[str, Any]:
    pr_info = check_ton_assets_pr()
    if not pr_info.get("ok") or pr_info.get("state") != "OPEN":
        return {"nudged": False, "reason": "pr_not_open"}
    proc = subprocess.run(
        [
            "gh",
            "pr",
            "comment",
            str(TON_ASSETS_PR),
            "--repo",
            TON_ASSETS_REPO,
            "--body",
            (
                "Phalanx Foundation automation follow-up: PLX mainnet LP live — "
                f"{STONFI_POOL_URL}. Ready for review — thank you."
            ),
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    return {
        "nudged": proc.returncode == 0,
        "stdout": proc.stdout[:200],
        "stderr": proc.stderr[:200],
    }


def eligibility_gates(liquidity_usd: float) -> dict[str, Any]:
    return {
        "coingecko_ready": liquidity_usd >= COINGECKO_MIN_LP_USD,
        "coingecko_min_usd": COINGECKO_MIN_LP_USD,
        "cmc_ready": liquidity_usd >= CMC_MIN_LP_USD,
        "cmc_min_usd": CMC_MIN_LP_USD,
        "liquidity_usd": liquidity_usd,
    }


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
