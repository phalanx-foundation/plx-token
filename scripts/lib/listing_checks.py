"""Platform status probes for multi-token listing automation.

Every checker accepts an optional `config` (TokenListingConfig) parameter.
When omitted, defaults to PLX for backward compatibility with existing scripts.
"""

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
    TONAPI_MIN_HOLDERS,
    TONAPI_MIN_TON_RESERVE,
    TON_ASSETS_REPO,
    TokenListingConfig,
    plx_config,
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


def _resolve_config(cfg: TokenListingConfig | None = None) -> TokenListingConfig:
    return cfg if cfg is not None else plx_config()


def check_dexscreener_pair(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    if not cfg.pool_address:
        return {"ok": False, "error": "no_pool_address", "url": ""}
    url = f"https://api.dexscreener.com/latest/dex/pairs/ton/{cfg.pool_address}"
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
        "url": cfg.dexscreener_url,
        "price_usd": pair.get("priceUsd") if pair else None,
        "txns_24h": pair.get("txns", {}).get("h24") if pair else None,
    }


def check_dexscreener_orders(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    url = f"https://api.dexscreener.com/orders/v1/ton/{cfg.minter_address}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "PLX-ListingAutomation/1.0"})
        with urllib.request.urlopen(req, timeout=30) as res:
            raw = res.read().decode()
            orders = json.loads(raw)
            return {"ok": True, "orders": orders if isinstance(orders, list) else []}
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return {"ok": False, "orders": []}


def check_tonapi_jetton(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    key = os.environ.get("TONAPI_KEY", os.environ.get("CONSOLE_TOKEN", "")).strip()
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    data = _http_json(f"https://tonapi.io/v2/jettons/{cfg.minter_address}", headers=headers)
    if not data:
        return {"ok": False, "error": "tonapi_unreachable_or_no_key"}
    return {
        "ok": True,
        "verification": data.get("verification"),
        "holders": data.get("holders_count"),
        "symbol": (data.get("metadata") or {}).get("symbol"),
    }


def check_dyor_indexed(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    body = json.dumps({"address": [cfg.minter_address], "limit": 1, "excludeScam": False}).encode()
    data = _http_json(
        "https://api.dyor.io/v1/jettons",
        method="POST",
        headers={"Content-Type": "application/json"},
        body=body,
    )
    jettons = data.get("jettons") if data else None
    found = isinstance(jettons, list) and len(jettons) > 0
    return {"ok": found, "indexed": found, "count": len(jettons or [])}


def check_coingecko_listed(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    query = f"{cfg.symbol}%20{cfg.name}"
    search = _http_json(f"https://api.coingecko.com/api/v3/search?query={query}")
    coins = (search or {}).get("coins") if search else []
    match = None
    name_lower = cfg.name.lower()
    if isinstance(coins, list):
        for c in coins:
            if isinstance(c, dict) and name_lower in (c.get("name") or "").lower():
                match = c
                break
    return {"ok": match is not None, "coin": match}


def check_ton_assets_pr(config: TokenListingConfig | None = None) -> dict[str, Any]:
    cfg = _resolve_config(config)
    if not cfg.ton_assets_pr:
        return {"ok": False, "error": "no_pr_number"}
    proc = subprocess.run(
        [
            "gh", "pr", "view", str(cfg.ton_assets_pr),
            "--repo", TON_ASSETS_REPO,
            "--json", "state,mergedAt,url,comments,updatedAt",
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


def nudge_ton_assets_pr_if_stale(
    config: TokenListingConfig | None = None,
    days: int = 14,
) -> dict[str, Any]:
    cfg = _resolve_config(config)
    pr_info = check_ton_assets_pr(cfg)
    if not pr_info.get("ok") or pr_info.get("state") != "OPEN":
        return {"nudged": False, "reason": "pr_not_open"}
    body_text = (
        f"Phalanx Foundation automation follow-up: {cfg.symbol} mainnet LP live — "
        f"{cfg.pool_url}. Ready for review — thank you."
    )
    proc = subprocess.run(
        [
            "gh", "pr", "comment", str(cfg.ton_assets_pr),
            "--repo", TON_ASSETS_REPO,
            "--body", body_text,
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


def check_stonfi_pool_ton(config: TokenListingConfig | None = None) -> dict[str, Any]:
    """Pool TON side from Ston.fi API (fallback when DexScreener de-indexed)."""
    cfg = _resolve_config(config)
    if not cfg.pool_address:
        return {"ok": False, "ton_human": None, "url": ""}
    data = _http_json(f"https://api.ston.fi/v1/pools/{cfg.pool_address}")
    pool = data.get("pool") if isinstance(data, dict) else None
    if not isinstance(pool, dict):
        return {"ok": False, "ton_human": None, "url": cfg.pool_url}
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
        "url": cfg.pool_url,
    }


def check_tonapi_rates(config: TokenListingConfig | None = None) -> dict[str, Any]:
    """Tonkeeper USD uses TonAPI /v2/rates — not Tonviewer verification."""
    cfg = _resolve_config(config)
    data = _http_json(
        f"https://tonapi.io/v2/rates?tokens={cfg.minter_address}&currencies=usd",
    )
    rates = data.get("rates") if data else None
    entry = None
    if isinstance(rates, dict):
        entry = rates.get(cfg.minter_address) or next(iter(rates.values()), None)
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
