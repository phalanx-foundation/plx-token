#!/usr/bin/env python3
"""
Phase 2 — Process buyback queue: Ston.fi TON→PLX swap then on-chain burn.

Cron (Ubuntu acton server, every 15 min):
  */15 * * * * cd ~/projects/plx-acton && bash scripts/process-buyback-queue.sh >> logs/buyback-queue.log 2>&1

Requires: STONFI_POOL_ADDRESS, JETTON_MINTER_ADDRESS, TONAPI or Ston.fi API access.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.stonfi_swap import simulate_ton_to_plx  # noqa: E402

QUEUE_FILE = Path(os.environ.get("BUYBACK_QUEUE_FILE", ROOT / "data" / "buyback-pending.json"))
MIN_SWAP_NANO = int(os.environ.get("BUYBACK_MIN_SWAP_NANO", str(500_000_000)))  # 0.5 TON
SLIPPAGE_BPS = int(os.environ.get("BUYBACK_SLIPPAGE_BPS", "300"))  # 3%


def _load_queue() -> list[dict]:
    if not QUEUE_FILE.exists():
        return []
    data = json.loads(QUEUE_FILE.read_text())
    return data if isinstance(data, list) else []


def _save_queue(entries: list[dict]) -> None:
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    QUEUE_FILE.write_text(json.dumps(entries, indent=2))


def _run_buyback_burn(plx_nano: int, network: str) -> bool:
    acton = os.environ.get("ACTON", str(Path.home() / ".acton/bin/acton"))
    env = os.environ.copy()
    env["PLX_BURN_AMOUNT"] = str(plx_nano)
    env.setdefault("PLX_BURNER", "plx-treasury")
    proc = subprocess.run(
        [acton, "script", "scripts/buyback-burn.tolk", "--net", network],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        env=env,
        check=False,
    )
    return proc.returncode == 0


def process_one(entry: dict) -> dict:
    """Mark entry processed or failed; returns updated entry."""
    if entry.get("status") != "pending":
        return entry

    network = entry.get("network", "mainnet")
    offer_nano = int(entry.get("buyback_nano", 0))
    if offer_nano < MIN_SWAP_NANO:
        entry["status"] = "skipped_below_min"
        return entry

    pool = os.environ.get("STONFI_POOL_ADDRESS", "").strip()
    if not pool:
        entry["status"] = "waiting_pool"
        entry["note"] = "Set STONFI_POOL_ADDRESS when PLX/TON pool is live"
        return entry

    quote = simulate_ton_to_plx(offer_nano, slippage=str(SLIPPAGE_BPS / 100))
    if not quote:
        entry["status"] = "swap_simulate_failed"
        return entry

    ask_units = int(quote.get("ask_units", 0) or 0)
    if ask_units <= 0:
        entry["status"] = "swap_zero_output"
        return entry

    # Phase 2a: record intended swap; full Ston.fi tx broadcast requires wallet SDK integration.
    # When STONFI_SWAP_ENABLED=true, operator enables automated swap path on server.
    if os.environ.get("STONFI_SWAP_ENABLED", "").lower() != "true":
        entry["status"] = "queued_for_manual_swap"
        entry["simulate_ask_units"] = ask_units
        return entry

    if not _run_buyback_burn(ask_units, network):
        entry["status"] = "burn_failed"
        return entry

    entry["status"] = "burned"
    entry["burned_plx_nano"] = ask_units
    return entry


def main() -> int:
    entries = _load_queue()
    if not entries:
        print("buyback queue empty")
        return 0

    changed = False
    for i, entry in enumerate(entries):
        if entry.get("status") != "pending":
            continue
        updated = process_one(entry)
        if updated != entry:
            entries[i] = updated
            changed = True

    if changed:
        _save_queue(entries)
    print(json.dumps({"processed": changed, "queue_size": len(entries)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
