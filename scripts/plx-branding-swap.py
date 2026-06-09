#!/usr/bin/env python3
"""
Disclosed liquidity-awareness swaps (micro market-making).

Cron (Ubuntu Acton, every 30 min):
  */30 * * * * cd ~/projects/plx-acton && python3 scripts/plx-branding-swap.py >> logs/branding-swap.log 2>&1

Requires: BRANDING_SWAP_ENABLED=true, STONFI_POOL_ADDRESS, acton wallets funded.
Optional broadcast: npm install in scripts/stonfi-swap + STONFI_SWAP_BROADCAST_ENABLED=true
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_FILE = Path(os.environ.get("BRANDING_SWAP_LOG", ROOT / "data" / "branding-swap-log.json"))
sys.path.insert(0, str(ROOT / "scripts"))

from lib.stonfi_swap import (  # noqa: E402
    enqueue_swap,
    load_swap_queue,
    run_node_executor,
    simulate_plx_to_ton,
    simulate_ton_to_plx,
    stonfi_pool_url,
)

STATE_FILE = Path(os.environ.get("BRANDING_SWAP_STATE", ROOT / "data" / "branding-swap-state.json"))


def _enabled() -> bool:
    return os.environ.get("BRANDING_SWAP_ENABLED", "").lower() == "true"


def _broadcast_enabled() -> bool:
    return os.environ.get("STONFI_SWAP_BROADCAST_ENABLED", "").lower() == "true"


def _int_env(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


def _load_state() -> dict:
    if not STATE_FILE.exists():
        return {"day": "", "ton_nano_today": 0, "swap_count_today": 0, "last_run": 0}
    try:
        return json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return {"day": "", "ton_nano_today": 0, "swap_count_today": 0, "last_run": 0}


def _save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def _append_log(entry: dict) -> None:
    logs: list = []
    if LOG_FILE.exists():
        try:
            raw = json.loads(LOG_FILE.read_text())
            logs = raw if isinstance(raw, list) else []
        except json.JSONDecodeError:
            logs = []
    logs.append(entry)
    if len(logs) > 500:
        logs = logs[-500:]
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    LOG_FILE.write_text(json.dumps(logs, indent=2) + "\n")


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _reset_day(state: dict) -> dict:
    if state.get("day") != _today():
        state["day"] = _today()
        state["ton_nano_today"] = 0
        state["swap_count_today"] = 0
    return state


def main() -> int:
    if not _enabled():
        print(json.dumps({"ok": True, "skipped": "BRANDING_SWAP_ENABLED false"}))
        return 0

    state = _reset_day(_load_state())
    now = int(time.time())
    min_interval = _int_env("BRANDING_MIN_INTERVAL_SEC", 1800)
    if now - int(state.get("last_run", 0)) < min_interval:
        print(json.dumps({"ok": True, "skipped": "interval"}))
        return 0

    max_ton_day = _int_env("BRANDING_MAX_TON_NANO_PER_DAY", 500_000_000)
    swap_ton = _int_env("BRANDING_SWAP_TON_NANO", 50_000_000)
    max_swaps = _int_env("BRANDING_MAX_SWAPS_PER_DAY", 8)

    if state["ton_nano_today"] + swap_ton > max_ton_day:
        print(json.dumps({"ok": True, "skipped": "daily_ton_cap"}))
        return 0
    if state["swap_count_today"] >= max_swaps:
        print(json.dumps({"ok": True, "skipped": "daily_swap_cap"}))
        return 0

    side = os.environ.get("BRANDING_SWAP_SIDE", "buy").strip().lower()
    wallet_buy = os.environ.get("BRANDING_WALLET_BUY", "plx-marketing").strip()
    wallet_sell = os.environ.get("BRANDING_WALLET_SELL", "plx-toolkit-ops").strip()
    wallet = wallet_buy if side == "buy" else wallet_sell
    network = os.environ.get("network", os.environ.get("NETWORK", "mainnet"))

    sim = simulate_ton_to_plx(swap_ton) if side == "buy" else simulate_plx_to_ton(swap_ton)
    if not sim:
        print(json.dumps({"ok": False, "error": "simulate_failed"}))
        return 1

    entry = {
        "queued_at": datetime.now(timezone.utc).isoformat(),
        "side": side,
        "wallet": wallet,
        "network": network,
        "units_nano": swap_ton,
        "simulation": {
            "ask_units": sim.get("ask_units"),
            "offer_units": sim.get("offer_units"),
            "router_address": sim.get("router_address"),
            "pool_address": sim.get("pool_address"),
        },
        "status": "simulated",
        "manual_url": stonfi_pool_url(),
        "note": "Disclosed liquidity-awareness — see docs/TRANSPARENCY.md",
    }

    if _broadcast_enabled():
        code, out, err = run_node_executor(side, swap_ton, wallet)
        entry["broadcast_exit"] = code
        entry["broadcast_stdout"] = out[-2000:] if out else ""
        entry["broadcast_stderr"] = err[-2000:] if err else ""
        entry["status"] = "broadcast_ok" if code == 0 else "broadcast_failed"
    else:
        enqueue_swap(entry)
        entry["status"] = "queued_manual"

    state["ton_nano_today"] = int(state["ton_nano_today"]) + swap_ton
    state["swap_count_today"] = int(state["swap_count_today"]) + 1
    state["last_run"] = now
    _save_state(state)
    _append_log(entry)

    print(json.dumps({"ok": True, "entry": entry}))
    return 0 if entry["status"] != "broadcast_failed" else 1


if __name__ == "__main__":
    sys.exit(main())
