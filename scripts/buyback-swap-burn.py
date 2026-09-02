#!/usr/bin/env python3
"""
Phase 2 — Process buyback queue: Ston.fi TON→PLX swap then on-chain burn.

Cron (Ubuntu acton server, every 15 min):
  */15 * * * * cd ~/projects/plx-acton && bash scripts/process-buyback-queue.sh >> logs/buyback-queue.log 2>&1

Requires: STONFI_POOL_ADDRESS, PLX_JETTON_MINTER_MAINNET, WALLETS_TOML on worker host.
Enable live path: STONFI_SWAP_ENABLED=true (swap broadcast + burn after credit).
Dry-run: DRY_RUN=true (simulate + build swap only; no burn).
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
sys.path.insert(0, str(ROOT / "scripts"))

from lib.stonfi_buyback import run_buyback_swap_executor
from lib.stonfi_swap import simulate_ton_to_plx

QUEUE_FILE = Path(
    os.environ.get("BUYBACK_QUEUE_FILE", ROOT / "data" / "buyback-pending.json")
)
MIN_SWAP_NANO = int(
    os.environ.get("BUYBACK_MIN_SWAP_NANO", str(500_000_000))
)  # 0.5 TON
SLIPPAGE_BPS = int(os.environ.get("BUYBACK_SLIPPAGE_BPS", "300"))  # 3%
GAS_RESERVE_NANO = int(os.environ.get("BUYBACK_GAS_RESERVE_NANO", str(300_000_000)))
JETTON_WAIT_SEC = int(os.environ.get("BUYBACK_JETTON_WAIT_SEC", "90"))
DEFAULT_TREASURY = "EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX"
DEFAULT_PLX_MINTER = "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"


def _slippage_str() -> str:
    return os.environ.get("STONFI_SLIPPAGE", str(SLIPPAGE_BPS / 10_000))


def _treasury_address() -> str:
    return (
        os.environ.get("TON_TREASURY_ADDRESS_MAINNET", "").strip()
        or os.environ.get("TON_TREASURY_ADDRESS", "").strip()
        or DEFAULT_TREASURY
    )


def _plx_minter() -> str:
    return (
        os.environ.get("PLX_JETTON_MINTER_MAINNET", "").strip()
        or os.environ.get("JETTON_MINTER_ADDRESS", "").strip()
        or DEFAULT_PLX_MINTER
    )


def _load_queue() -> list[dict]:
    if not QUEUE_FILE.exists():
        return []
    data = json.loads(QUEUE_FILE.read_text())
    return data if isinstance(data, list) else []


def _save_queue(entries: list[dict]) -> None:
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    QUEUE_FILE.write_text(json.dumps(entries, indent=2) + "\n")


def _ton_balance_nano(address: str) -> int | None:
    api_key = os.environ.get("TONCENTER_MAINNET_API_KEY", "").strip()
    url = f"https://toncenter.com/api/v2/getAddressBalance?address={address}"
    if api_key:
        url += f"&api_key={api_key}"
    try:
        with urllib.request.urlopen(url, timeout=20) as res:
            data = json.loads(res.read().decode())
            if data.get("ok") and data.get("result") is not None:
                return int(data["result"])
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError):
        return None
    return None


def _treasury_plx_nano() -> int | None:
    """Best-effort PLX jetton balance for treasury via TonAPI."""
    treasury = _treasury_address()
    minter = _plx_minter()
    base = os.environ.get("TONAPI_MAINNET_BASE", "https://tonapi.io/v2").rstrip("/")
    url = f"{base}/accounts/{treasury}/jettons"
    headers: dict[str, str] = {"Accept": "application/json"}
    api_key = os.environ.get("TONAPI_KEY", "").strip()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            data = json.loads(res.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None
    balances = data.get("balances") if isinstance(data, dict) else None
    if not isinstance(balances, list):
        return None
    for item in balances:
        if not isinstance(item, dict):
            continue
        jetton = item.get("jetton") or {}
        addr = (
            jetton.get("address")
            or item.get("jetton_address")
            or item.get("address")
        )
        if not addr:
            continue
        if minter in str(addr) or str(addr) in minter:
            bal = item.get("balance") or item.get("quantity")
            if bal is not None:
                return int(bal)
    return 0


def _wait_plx_credit(before_nano: int, min_expected: int) -> int | None:
    deadline = time.time() + JETTON_WAIT_SEC
    while time.time() < deadline:
        current = _treasury_plx_nano()
        if current is not None and current - before_nano >= min_expected:
            return current - before_nano
        time.sleep(5)
    after = _treasury_plx_nano()
    if after is not None and after > before_nano:
        return after - before_nano
    return None


def _run_buyback_burn(plx_nano: int, network: str) -> tuple[bool, str]:
    acton = os.environ.get("ACTON", str(Path.home() / ".acton/bin/acton"))
    env = os.environ.copy()
    env["PLX_BURN_AMOUNT"] = str(plx_nano)
    env.setdefault("PLX_BURNER", "plx-treasury")
    env.setdefault("JETTON_MINTER_ADDRESS", _plx_minter())
    proc = subprocess.run(
        [acton, "script", "scripts/buyback-burn.tolk", "--net", network],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        env=env,
        check=False,
    )
    detail = (proc.stderr or proc.stdout or "").strip()[-2000:]
    return proc.returncode == 0, detail


def _parse_swap_json(stdout: str) -> dict:
    text = (stdout or "").strip()
    if not text:
        return {}
    # Node may log warnings before JSON — take last JSON object line.
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                parsed = json.loads(line)
                return parsed if isinstance(parsed, dict) else {}
            except json.JSONDecodeError:
                continue
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {}


def process_one(entry: dict) -> dict:
    """Mark entry processed or failed; returns updated entry."""
    status = entry.get("status", "pending")
    if status not in {"pending", "swap_broadcast"}:
        return entry

    network = entry.get("network", "mainnet")
    if network != "mainnet":
        entry["status"] = "skipped_testnet"
        return entry

    offer_nano = int(entry.get("buyback_nano", 0))
    if offer_nano < MIN_SWAP_NANO:
        entry["status"] = "skipped_below_min"
        return entry

    pool = os.environ.get("STONFI_POOL_ADDRESS", "").strip()
    if not pool:
        entry["status"] = "waiting_pool"
        entry["note"] = "Set STONFI_POOL_ADDRESS when PLX/TON pool is live"
        return entry

    swap_enabled = os.environ.get("STONFI_SWAP_ENABLED", "").lower() == "true"
    dry_run = os.environ.get("DRY_RUN", "").lower() == "true"

    quote = simulate_ton_to_plx(offer_nano, slippage=_slippage_str())
    if not quote:
        entry["status"] = "swap_simulate_failed"
        return entry

    ask_units = int(quote.get("ask_units") or quote.get("min_ask_units") or 0)
    min_ask_units = int(quote.get("min_ask_units") or ask_units or 0)
    if ask_units <= 0:
        entry["status"] = "swap_zero_output"
        return entry

    entry["simulate_ask_units"] = ask_units
    entry["simulate_min_ask_units"] = min_ask_units

    if not swap_enabled and not dry_run:
        entry["status"] = "queued_for_manual_swap"
        return entry

    if status == "swap_broadcast":
        credited = _wait_plx_credit(
            int(entry.get("plx_balance_before_nano", 0)),
            int(entry.get("min_ask_units", min_ask_units)),
        )
        if credited is None or credited <= 0:
            entry["status"] = "swap_credit_timeout"
            return entry
        burn_nano = min(credited, int(entry.get("min_ask_units", min_ask_units)))
        ok, detail = _run_buyback_burn(burn_nano, network)
        entry["burn_detail"] = detail
        if not ok:
            entry["status"] = "burn_failed"
            return entry
        entry["status"] = "burned"
        entry["burned_plx_nano"] = burn_nano
        entry["credited_plx_nano"] = credited
        return entry

    ton_bal = _ton_balance_nano(_treasury_address())
    if ton_bal is not None and not dry_run:
        usable = max(0, ton_bal - GAS_RESERVE_NANO)
        if usable < MIN_SWAP_NANO:
            entry["status"] = "insufficient_treasury_ton"
            entry["ton_balance_nano"] = ton_bal
            return entry
        offer_nano = min(offer_nano, usable)

    plx_before = _treasury_plx_nano()
    if plx_before is None:
        plx_before = 0

    code, out, err = run_buyback_swap_executor(offer_nano, dry_run=dry_run)
    swap_result = _parse_swap_json(out)
    entry["swap_exit"] = code
    entry["swap_stdout"] = (out or "")[-4000:]
    entry["swap_stderr"] = (err or "")[-2000:]

    if code != 0 or not swap_result.get("ok"):
        entry["status"] = "swap_broadcast_failed"
        entry["error"] = swap_result.get("error") or err or out or "swap failed"
        return entry

    burn_plx = int(
        swap_result.get("min_ask_units")
        or swap_result.get("ask_units")
        or min_ask_units
    )
    entry["min_ask_units"] = burn_plx
    entry["plx_balance_before_nano"] = plx_before

    if dry_run:
        entry["status"] = "buyback_dry_run"
        entry["swap_result"] = swap_result
        return entry

    entry["status"] = "swap_broadcast"
    entry["swap_tx"] = swap_result
    credited = _wait_plx_credit(plx_before, burn_plx)
    if credited is None or credited <= 0:
        entry["note"] = "swap sent; burn deferred until jetton credit (re-run cron)"
        return entry

    burn_nano = min(credited, burn_plx)
    ok, detail = _run_buyback_burn(burn_nano, network)
    entry["burn_detail"] = detail
    if not ok:
        entry["status"] = "burn_failed"
        entry["credited_plx_nano"] = credited
        return entry

    entry["status"] = "burned"
    entry["burned_plx_nano"] = burn_nano
    entry["credited_plx_nano"] = credited
    return entry


def main() -> int:
    entries = _load_queue()
    if not entries:
        print("buyback queue empty")
        return 0

    changed = False
    for i, entry in enumerate(entries):
        if entry.get("status") not in {"pending", "swap_broadcast"}:
            continue
        old_status = entry.get("status")
        updated = process_one(entry)
        entries[i] = updated
        if updated.get("status") != old_status:
            changed = True

    if changed:
        _save_queue(entries)
    print(json.dumps({"processed": changed, "queue_size": len(entries)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
