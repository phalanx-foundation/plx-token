#!/usr/bin/env python3
"""
Ston.fi LP automation for treasury sweep 25% slice.

Flow:
  1. If STONFI_LP_AUTO_ENABLED + pool known → simulate via api.ston.fi
  2. If STONFI_LP_BROADCAST_ENABLED → queue for router broadcast (Phase 3b)
  3. Else fallback: TON transfer to plx-lp (Phase 1)

Testnet: Ston.fi API is mainnet-only → always fallback transfer + optional lp queue.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STONFI_API = os.environ.get("STONFI_API_BASE", "https://api.ston.fi").rstrip("/")
MIN_LP_NANO = int(os.environ.get("STONFI_LP_MIN_NANO", str(10_000_000)))  # 0.01 TON
SLIPPAGE = os.environ.get("STONFI_LP_SLIPPAGE", "0.01")
TON_NATIVE = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"


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
        os.environ.get("PLX_LP_ADDRESS_MAINNET", "EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH"),
    ).strip()


def _queue_lp(entry: dict) -> None:
    queue_path = Path(os.environ.get("LP_QUEUE_FILE", ROOT / "data" / "lp-pending.json"))
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
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            parsed = json.loads(res.read().decode())
            return parsed if isinstance(parsed, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def _resolve_pool(plx_jetton: str) -> str | None:
    explicit = os.environ.get("STONFI_POOL_ADDRESS", "").strip()
    if explicit:
        return explicit
    # Ston.fi market lookup (mainnet)
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


def _simulate_balanced(pool: str, plx_jetton: str, ton_nano: int, wallet: str) -> dict | None:
    body = {
        "provision_type": "Balanced",
        "pool_address": pool,
        "slippage_tolerance": SLIPPAGE,
        "token_a": TON_NATIVE,
        "token_b": plx_jetton,
        "token_a_units": str(ton_nano),
        "wallet_address": wallet,
    }
    return _http_json("POST", f"{STONFI_API}/v1/liquidity_provision/simulate", body)


def add_liquidity(ton_nano: int, network: str) -> dict:
    deployment_id = os.environ.get("DEPLOYMENT_ID", "unknown")
    lp_address = _lp_wallet(network)

    if ton_nano < MIN_LP_NANO:
        return {"mode": "skipped", "ok": True, "reason": "below_min", "ton_nano": ton_nano}

    auto = os.environ.get("STONFI_LP_AUTO_ENABLED", "").lower() == "true"
    plx_jetton = _jetton_minter(network)

    if network == "testnet" or not auto:
        result = _fallback_transfer(ton_nano, lp_address, network)
        result["deployment_id"] = deployment_id
        result["note"] = "testnet_or_auto_disabled"
        return result

    if not plx_jetton:
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
        return _fallback_transfer(ton_nano, lp_address, network) | {
            "mode": "fallback_no_pool",
            "queued": True,
        }

    sim = _simulate_balanced(pool, plx_jetton, ton_nano, lp_address)
    if not sim:
        return _fallback_transfer(ton_nano, lp_address, network) | {"mode": "fallback_simulate_failed"}

    entry = {
        "deployment_id": deployment_id,
        "network": network,
        "ton_nano": ton_nano,
        "pool": pool,
        "simulation": sim,
        "status": "simulated",
        "queued_at": int(time.time()),
    }

    if os.environ.get("STONFI_LP_BROADCAST_ENABLED", "").lower() == "true":
        entry["status"] = "pending_broadcast"
        _queue_lp(entry)
        return {
            "mode": "stonfi_queued_broadcast",
            "ok": True,
            "pool": pool,
            "ton_nano": ton_nano,
            "min_lp_units": sim.get("min_lp_units"),
        }

    _queue_lp(entry)
    fallback = _fallback_transfer(ton_nano, lp_address, network)
    fallback["mode"] = "fallback_until_lp_broadcast"
    fallback["pool"] = pool
    fallback["simulated"] = True
    return fallback


def main() -> int:
    ton_nano = int(os.environ.get("LP_TON_NANO", "0"))
    network = os.environ.get("network", os.environ.get("NETWORK", "mainnet"))
    if ton_nano <= 0:
        print(json.dumps({"error": "LP_TON_NANO required"}))
        return 1
    result = add_liquidity(ton_nano, network)
    print(json.dumps(result))
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    sys.exit(main())
