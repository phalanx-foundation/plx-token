#!/usr/bin/env python3
"""
Ston.fi LP automation for treasury sweep + buy-side thickener.

Flow:
  1. If STONFI_LP_AUTO_ENABLED + pool known → simulate via api.ston.fi
  2. If STONFI_LP_BROADCAST_ENABLED → broadcast provide_lp from plx-lp (Phase 3b)
  3. Else: queue simulation + optional TON transfer to plx-lp (Phase 1)

Buy-side thickening already parks GRAM in plx-lp, so that path skips the
treasury→LP transfer and only needs the router broadcast.

Testnet: Ston.fi API is mainnet-only → always fallback transfer + optional lp queue.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.stonfi_lp import run_lp_executor

STONFI_API = os.environ.get("STONFI_API_BASE", "https://api.ston.fi").rstrip("/")
MIN_LP_NANO = int(os.environ.get("STONFI_LP_MIN_NANO", str(10_000_000)))  # 0.01 TON
# Gas for the two provide_lp legs; leave this much TON in the LP wallet.
GAS_RESERVE_NANO = int(os.environ.get("STONFI_LP_GAS_RESERVE_NANO", str(200_000_000)))
SLIPPAGE = os.environ.get("STONFI_LP_SLIPPAGE", "0.01")
TON_NATIVE = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
DEFAULT_POOL = "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq"
DEFAULT_LP = "EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH"


def _jetton_minter(network: str) -> str:
    if network == "mainnet":
        return os.environ.get(
            "PLX_JETTON_MINTER_MAINNET",
            os.environ.get("JETTON_MINTER_ADDRESS", ""),
        ).strip()
    return os.environ.get(
        "PLX_JETTON_MINTER",
        "kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV",
    ).strip()


def _lp_wallet(network: str) -> str:
    if network == "testnet":
        return os.environ.get(
            "PLX_LP_ADDRESS",
            "kQD4-ER4sDGmw4PcPPJ-AwLYG9TORvZ5sJ-xNKthunKz0AOP",
        ).strip()
    return os.environ.get(
        "PLX_LP_ADDRESS",
        os.environ.get("PLX_LP_ADDRESS_MAINNET", DEFAULT_LP),
    ).strip()


def _funds_already_in_lp() -> bool:
    """Thickener and explicit flags skip the treasury→LP hop."""
    if os.environ.get("LP_FUNDS_IN_WALLET", "").lower() in {"1", "true", "yes"}:
        return True
    return os.environ.get("DEPLOYMENT_ID", "").strip() == "lp-thickener"


def _queue_lp(entry: dict) -> None:
    queue_path = Path(
        os.environ.get("LP_QUEUE_FILE", ROOT / "data" / "lp-pending.json")
    )
    queue_path.parent.mkdir(parents=True, exist_ok=True)
    entries: list = []
    if queue_path.exists():
        try:
            raw = json.loads(queue_path.read_text())
            entries = raw if isinstance(raw, list) else []
        except json.JSONDecodeError:
            entries = []
    entries.append(entry)
    queue_path.write_text(json.dumps(entries, indent=2))


def _fallback_transfer(ton_nano: int, lp_address: str, network: str) -> dict:
    acton = os.environ.get("ACTON", str(Path.home() / ".acton/bin/acton"))
    env = os.environ.copy()
    env["FROM_WALLET"] = "plx-treasury"
    env["TO_ADDRESS"] = lp_address
    env["TON_AMOUNT"] = str(ton_nano)
    proc = subprocess.run(
        [acton, "script", "scripts/send-ton.tolk", "--net", network],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        env=env,
        check=False,
    )
    return {
        "mode": "fallback_transfer",
        "ok": proc.returncode == 0,
        "ton_nano": ton_nano,
        "lp_address": lp_address,
    }


def _http_json(method: str, url: str, body: dict | None = None) -> dict | None:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "plx-lp/1.0",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            parsed = json.loads(res.read().decode())
            return parsed if isinstance(parsed, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def _http_query_post(url: str, params: dict[str, str]) -> dict | None:
    """Ston.fi simulate endpoints take query-string params (not JSON body)."""
    full = f"{url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(
        full,
        data=b"",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "plx-lp/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            parsed = json.loads(res.read().decode())
            return parsed if isinstance(parsed, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def _resolve_pool(plx_jetton: str) -> str | None:
    explicit = os.environ.get("STONFI_POOL_ADDRESS", "").strip() or DEFAULT_POOL
    if explicit:
        return explicit
    url = f"{STONFI_API}/v1/pools/by_market/{TON_NATIVE}/{plx_jetton}"
    data = _http_json("GET", url)
    if not data:
        return None
    pools = data.get("pool_list") or data.get("pools") or []
    if isinstance(pools, list) and pools:
        first = pools[0]
        if isinstance(first, dict):
            addr = first.get("address") or first.get("pool_address")
            return str(addr) if addr else None
    return None


def _simulate_balanced(
    pool: str, plx_jetton: str, ton_nano: int, wallet: str
) -> dict | None:
    # Official API: POST /v1/liquidity_provision/simulate with *query* params.
    # JSON body returns 400 missing field `provision_type`.
    return _http_query_post(
        f"{STONFI_API}/v1/liquidity_provision/simulate",
        {
            "provision_type": "Balanced",
            "pool_address": pool,
            "slippage_tolerance": SLIPPAGE,
            "token_a": TON_NATIVE,
            "token_b": plx_jetton,
            "token_a_units": str(ton_nano),
            "wallet_address": wallet,
        },
    )


def _lp_ton_balance_nano(lp_address: str) -> int | None:
    """Best-effort on-chain TON balance via toncenter (no key required for small qps)."""
    api_key = os.environ.get("TONCENTER_MAINNET_API_KEY", "").strip()
    url = "https://toncenter.com/api/v2/getAddressBalance"
    params = f"?address={lp_address}"
    if api_key:
        params += f"&api_key={api_key}"
    try:
        with urllib.request.urlopen(url + params, timeout=20) as res:
            data = json.loads(res.read().decode())
            if data.get("ok") and data.get("result") is not None:
                return int(data["result"])
    except (
        urllib.error.URLError,
        json.JSONDecodeError,
        TimeoutError,
        TypeError,
        ValueError,
    ):
        return None
    return None


def add_liquidity(ton_nano: int, network: str) -> dict:
    deployment_id = os.environ.get("DEPLOYMENT_ID", "unknown")
    lp_address = _lp_wallet(network)
    already_funded = _funds_already_in_lp()

    if ton_nano < MIN_LP_NANO:
        return {
            "mode": "skipped",
            "ok": True,
            "reason": "below_min",
            "ton_nano": ton_nano,
        }

    auto = os.environ.get("STONFI_LP_AUTO_ENABLED", "").lower() == "true"
    broadcast = os.environ.get("STONFI_LP_BROADCAST_ENABLED", "").lower() == "true"
    dry_run = os.environ.get("DRY_RUN", "").lower() == "true"
    plx_jetton = _jetton_minter(network)

    if network == "testnet" or not auto:
        if already_funded:
            return {
                "mode": "skipped",
                "ok": True,
                "reason": "testnet_or_auto_disabled",
                "ton_nano": ton_nano,
                "deployment_id": deployment_id,
            }
        result = _fallback_transfer(ton_nano, lp_address, network)
        result["deployment_id"] = deployment_id
        result["note"] = "testnet_or_auto_disabled"
        return result

    if not plx_jetton:
        if already_funded:
            return {
                "mode": "skipped",
                "ok": False,
                "error": "missing_plx_jetton_minter",
            }
        result = _fallback_transfer(ton_nano, lp_address, network)
        result["note"] = "missing_plx_jetton_minter"
        return result

    pool = _resolve_pool(plx_jetton)
    if not pool:
        _queue_lp(
            {
                "deployment_id": deployment_id,
                "network": network,
                "ton_nano": ton_nano,
                "status": "waiting_pool",
                "queued_at": int(time.time()),
            }
        )
        if already_funded:
            return {
                "mode": "fallback_no_pool",
                "ok": False,
                "queued": True,
                "ton_nano": ton_nano,
            }
        return _fallback_transfer(ton_nano, lp_address, network) | {
            "mode": "fallback_no_pool",
            "queued": True,
        }

    # Cap liquidity by live balance minus gas when funds already sit in plx-lp.
    spend_nano = ton_nano
    if (already_funded or broadcast) and not dry_run:
        bal = _lp_ton_balance_nano(lp_address)
        if bal is not None:
            usable = max(0, bal - GAS_RESERVE_NANO)
            if usable < MIN_LP_NANO:
                return {
                    "mode": "insufficient_lp_ton",
                    "ok": False,
                    "ton_balance_nano": bal,
                    "gas_reserve_nano": GAS_RESERVE_NANO,
                    "requested_nano": ton_nano,
                    "error": "plx-lp needs more TON (liquidity + gas reserve)",
                }
            spend_nano = min(ton_nano, usable)

    sim = _simulate_balanced(pool, plx_jetton, spend_nano, lp_address)
    if not sim:
        if already_funded:
            return {
                "mode": "fallback_simulate_failed",
                "ok": False,
                "ton_nano": spend_nano,
            }
        return _fallback_transfer(ton_nano, lp_address, network) | {
            "mode": "fallback_simulate_failed"
        }

    entry = {
        "deployment_id": deployment_id,
        "network": network,
        "ton_nano": spend_nano,
        "pool": pool,
        "simulation": {
            "min_lp_units": sim.get("min_lp_units") or sim.get("minLpUnits"),
            "token_a_units": sim.get("token_a_units") or sim.get("tokenAUnits"),
            "token_b_units": sim.get("token_b_units") or sim.get("tokenBUnits"),
            "router_address": sim.get("router_address") or sim.get("routerAddress"),
        },
        "status": "simulated",
        "queued_at": int(time.time()),
    }

    if broadcast:
        # Treasury-sweep path still needs the TON on plx-lp before broadcasting.
        if not already_funded:
            moved = _fallback_transfer(spend_nano, lp_address, network)
            entry["prefund"] = moved
            if not moved.get("ok"):
                entry["status"] = "prefund_failed"
                _queue_lp(entry)
                return {
                    "mode": "prefund_failed",
                    "ok": False,
                    "pool": pool,
                    "ton_nano": spend_nano,
                    "entry": entry,
                }

        code, out, err = run_lp_executor(spend_nano, dry_run=dry_run)
        entry["broadcast_exit"] = code
        entry["broadcast_stdout"] = (out or "")[-4000:]
        entry["broadcast_stderr"] = (err or "")[-2000:]
        try:
            parsed = json.loads(out) if out else {}
        except json.JSONDecodeError:
            parsed = {}
        if code == 0 and parsed.get("ok"):
            entry["status"] = "broadcast" if not dry_run else "dry_run"
            _queue_lp(entry)
            return {
                "mode": "stonfi_broadcast" if not dry_run else "stonfi_lp_dry_run",
                "ok": True,
                "pool": pool,
                "ton_nano": spend_nano,
                "min_lp_units": entry["simulation"].get("min_lp_units"),
                "result": parsed,
                "deployment_id": deployment_id,
            }
        entry["status"] = "broadcast_failed"
        _queue_lp(entry)
        return {
            "mode": "stonfi_broadcast_failed",
            "ok": False,
            "pool": pool,
            "ton_nano": spend_nano,
            "error": parsed.get("error") or err or out or "broadcast failed",
            "deployment_id": deployment_id,
        }

    _queue_lp(entry)
    if already_funded:
        return {
            "mode": "queued_until_lp_broadcast",
            "ok": True,
            "pool": pool,
            "ton_nano": spend_nano,
            "simulated": True,
            "deployment_id": deployment_id,
        }
    fallback = _fallback_transfer(ton_nano, lp_address, network)
    fallback["mode"] = "fallback_until_lp_broadcast"
    fallback["pool"] = pool
    fallback["simulated"] = True
    return fallback


def main() -> int:
    ton_nano = int(os.environ.get("LP_TON_NANO", "0"))
    network = os.environ.get("NETWORK", "mainnet")
    if ton_nano <= 0:
        print(json.dumps({"error": "LP_TON_NANO required"}))
        return 1
    result = add_liquidity(ton_nano, network)
    print(json.dumps(result))
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    sys.exit(main())
