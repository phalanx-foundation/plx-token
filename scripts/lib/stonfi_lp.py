"""Ston.fi LP broadcast helpers (mainnet)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from lib.wallet_mnemonic import load_wallet_mnemonic

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_LP_WALLET = "plx-lp"
DEFAULT_LP_ADDRESS = "EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH"


def run_lp_executor(ton_nano: int, *, wallet_name: str = DEFAULT_LP_WALLET, dry_run: bool = False) -> tuple[int, str, str]:
    """Run scripts/stonfi-swap/execute-lp.mjs with the LP wallet mnemonic."""
    script = ROOT / "scripts" / "stonfi-swap" / "execute-lp.mjs"
    if not script.is_file():
        return 1, "", "execute-lp.mjs missing"

    mnemonic = os.environ.get("TON_OPERATOR_MNEMONIC", "").strip()
    if not mnemonic:
        mnemonic = load_wallet_mnemonic(wallet_name) or ""
    if not mnemonic:
        return 1, "", f"mnemonic missing for {wallet_name}"

    env = os.environ.copy()
    env["TON_OPERATOR_MNEMONIC"] = mnemonic
    env["LP_TON_NANO"] = str(ton_nano)
    env["FROM_WALLET"] = wallet_name
    env["NETWORK"] = env.get("NETWORK", env.get("network", "mainnet"))
    if dry_run:
        env["DRY_RUN"] = "true"
    # Always pin the expected address so a wrong mnemonic cannot drain funds elsewhere.
    env.setdefault(
        "EXPECTED_WALLET_ADDRESS",
        env.get("PLX_LP_ADDRESS_MAINNET")
        or env.get("PLX_LP_ADDRESS")
        or DEFAULT_LP_ADDRESS,
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
