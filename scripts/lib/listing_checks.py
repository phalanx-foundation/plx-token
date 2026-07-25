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
    TONAPI_MIN_HOLDERS,
    TONAPI_MIN_TON_RESERVE,
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
    liq_obj = pair.get("liquidity") if pair else {}
    quote_reserve = None
    if isinstance(liq_obj, dict) and liq_obj.get("quote") is not None:
        try:
            quote_reserve = float(liq_obj.get("quote") or 0)
        except (TypeError, ValueError):
            quote_reserve = None
    return {
        "ok": pair is not None,
        "liquidity_usd": liq,
        "pool_ton_quote": quote_reserve,
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


def check_stonfi_pool_ton() -> dict[str, Any]:
    """Pool TON side from Ston.fi API (fallback when DexScreener de-indexed)."""
    data = _http_json(f"https://api.ston.fi/v1/pools/{STONFI_POOL}")
    pool = data.get("pool") if isinstance(data, dict) else None
    if not isinstance(pool, dict):
        return {"ok": False, "ton_human": None}
    ton_addr = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
    t0 = pool.get("token0_address") or ""
    t1 = pool.get("token1_address") or ""
    r0 = pool.get("token0_reserve") or pool.get("reserve0")
    r1 = pool.get("token1_reserve") or pool.get("reserve1")
    ton_human = None
    try:
        if t0 == ton_addr and r0:
            ton_human = int(r0) / 1e9
        elif t1 == ton_addr and r1:
            ton_human = int(r1) / 1e9
    except (TypeError, ValueError):
        ton_human = None
    return {
        "ok": ton_human is not None and ton_human > 0,
        "ton_human": ton_human,
        "url": STONFI_POOL_URL,
    }


def check_tonapi_rates() -> dict[str, Any]:
    """Tonkeeper USD uses TonAPI /v2/rates — not Tonviewer verification."""
    data = _http_json(
        f"https://tonapi.io/v2/rates?tokens={PLX_MINTER}&currencies=usd",
    )
    rates = data.get("rates") if data else None
    entry = None
    if isinstance(rates, dict):
        entry = rates.get(PLX_MINTER) or next(iter(rates.values()), None)
    usd_raw = (entry or {}).get("prices", {}).get("USD")
    try:
        usd = float(usd_raw) if usd_raw is not None else 0.0
    except (TypeError, ValueError):
        usd = 0.0
    return {
        "ok": usd > 0,
        "usd": usd,
        "price_ready": usd > 0,
        "diff_24h": (entry or {}).get("diff_24h", {}).get("USD"),
    }


def tonapi_price_gates(
    *,
    holders: int | None,
    pool_ton_quote: float | None,
    usd_price: float,
) -> dict[str, Any]:
    holders_n = int(holders or 0)
    pool_ton = float(pool_ton_quote or 0)
    return {
        "tonapi_price_ready": usd_price > 0,
        "holders_ready": holders_n >= TONAPI_MIN_HOLDERS,
        "pool_ton_ready": pool_ton >= TONAPI_MIN_TON_RESERVE,
        "holders": holders_n,
        "pool_ton_quote": pool_ton,
        "usd_price": usd_price,
        "min_holders": TONAPI_MIN_HOLDERS,
        "min_ton_reserve": TONAPI_MIN_TON_RESERVE,
        "tonkeeper_usd_ready": (
            usd_price > 0
            and holders_n >= TONAPI_MIN_HOLDERS
            and pool_ton >= TONAPI_MIN_TON_RESERVE
        ),
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
