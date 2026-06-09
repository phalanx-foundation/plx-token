"""Ston.fi swap simulate + queue helpers (mainnet)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

STONFI_API = os.environ.get("STONFI_API_BASE", "https://api.ston.fi").rstrip("/")
TON_NATIVE = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
ROOT = Path(__file__).resolve().parent.parent.parent
SWAP_QUEUE = Path(os.environ.get("SWAP_QUEUE_FILE", ROOT / "data" / "swap-pending.json"))


def _pool() -> str:
    return os.environ.get(
        "STONFI_POOL_ADDRESS",
        "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq",
    ).strip()


def _plx_minter() -> str:
    return os.environ.get(
        "PLX_JETTON_MINTER_MAINNET",
        os.environ.get("JETTON_MINTER_ADDRESS", "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"),
    ).strip()


def _http_post_query(path: str, params: dict[str, str]) -> dict[str, Any] | None:
    qs = urllib.parse.urlencode(params)
    url = f"{STONFI_API}{path}?{qs}"
    req = urllib.request.Request(
        url,
        data=b"",
        headers={"User-Agent": "PLX-StonfiSwap/1.0", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as res:
            data = json.loads(res.read().decode())
            return data if isinstance(data, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def simulate_ton_to_plx(ton_nano: int, slippage: str = "0.03") -> dict[str, Any] | None:
    """Buy PLX with TON."""
    return _http_post_query(
        "/v1/swap/simulate",
        {
            "offer_address": TON_NATIVE,
            "ask_address": _plx_minter(),
            "units": str(ton_nano),
            "pool_address": _pool(),
            "slippage_tolerance": slippage,
        },
    )


def simulate_plx_to_ton(plx_nano: int, slippage: str = "0.03") -> dict[str, Any] | None:
    """Sell PLX for TON (reverse simulate: target TON out in nano)."""
    return _http_post_query(
        "/v1/reverse_swap/simulate",
        {
            "offer_address": _plx_minter(),
            "ask_address": TON_NATIVE,
            "units": str(plx_nano),
            "pool_address": _pool(),
            "slippage_tolerance": slippage,
        },
    )


def stonfi_pool_url() -> str:
    return f"https://app.ston.fi/pools/{_pool()}"


def load_swap_queue() -> list[dict[str, Any]]:
    if not SWAP_QUEUE.exists():
        return []
    try:
        data = json.loads(SWAP_QUEUE.read_text())
        return data if isinstance(data, list) else []
    except json.JSONDecodeError:
        return []


def save_swap_queue(entries: list[dict[str, Any]]) -> None:
    SWAP_QUEUE.parent.mkdir(parents=True, exist_ok=True)
    SWAP_QUEUE.write_text(json.dumps(entries, indent=2) + "\n")


def enqueue_swap(entry: dict[str, Any]) -> None:
    entries = load_swap_queue()
    entries.append(entry)
    save_swap_queue(entries)


def run_node_executor(side: str, units: int, wallet: str) -> tuple[int, str, str]:
    """Run scripts/stonfi-swap/execute.mjs if npm deps installed on server."""
    script = ROOT / "scripts" / "stonfi-swap" / "execute.mjs"
    if not script.is_file():
        return 1, "", "execute.mjs missing"
    env = os.environ.copy()
    env["SWAP_SIDE"] = side
    env["SWAP_UNITS"] = str(units)
    env["FROM_WALLET"] = wallet
    env["NETWORK"] = env.get("network", env.get("NETWORK", "mainnet"))
    import subprocess

    proc = subprocess.run(
        ["node", str(script)],
        capture_output=True,
        text=True,
        cwd=str(ROOT / "scripts" / "stonfi-swap"),
        env=env,
        timeout=120,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr
