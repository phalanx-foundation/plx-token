"""Ston.fi buyback swap helpers (plx-treasury W5, mainnet)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from lib.wallet_mnemonic import load_wallet_mnemonic

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_TREASURY_WALLET = "plx-treasury"
DEFAULT_TREASURY_ADDRESS = "EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX"


def run_buyback_swap_executor(
    ton_nano: int,
    *,
    wallet_name: str = DEFAULT_TREASURY_WALLET,
    dry_run: bool = False,
) -> tuple[int, str, str]:
    """Run scripts/stonfi-swap/execute-buyback.mjs from plx-treasury."""
    script = ROOT / "scripts" / "stonfi-swap" / "execute-buyback.mjs"
    if not script.is_file():
        return 1, "", "execute-buyback.mjs missing"

    mnemonic = os.environ.get("TON_OPERATOR_MNEMONIC", "").strip()
    if not mnemonic:
        mnemonic = load_wallet_mnemonic(wallet_name) or ""
    if not mnemonic:
        return 1, "", f"mnemonic missing for {wallet_name}"

    slippage_bps = int(os.environ.get("BUYBACK_SLIPPAGE_BPS", "300"))
    slippage = os.environ.get(
        "STONFI_SLIPPAGE", str(slippage_bps / 10_000)
    )

    env = os.environ.copy()
    env["TON_OPERATOR_MNEMONIC"] = mnemonic
    env["SWAP_UNITS"] = str(ton_nano)
    env["SWAP_SIDE"] = "buy"
    env["FROM_WALLET"] = wallet_name
    env["STONFI_SLIPPAGE"] = slippage
    env["NETWORK"] = env.get("NETWORK", env.get("network", "mainnet"))
    if dry_run:
        env["DRY_RUN"] = "true"
    env.setdefault(
        "EXPECTED_WALLET_ADDRESS",
        env.get("TON_TREASURY_ADDRESS_MAINNET")
        or env.get("TON_TREASURY_ADDRESS")
        or DEFAULT_TREASURY_ADDRESS,
    )

    proc = subprocess.run(
        ["node", str(script)],
        capture_output=True,
        text=True,
        cwd=str(ROOT / "scripts" / "stonfi-swap"),
        env=env,
        timeout=180,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr
