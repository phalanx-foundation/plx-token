"""Load an Acton wallets.toml mnemonic for ops scripts (never print the words)."""

from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def wallets_toml_path() -> Path:
    explicit = os.environ.get("WALLETS_TOML", "").strip()
    if explicit:
        return Path(explicit)
    return ROOT / "wallets.toml"


def load_wallet_mnemonic(wallet_name: str) -> str | None:
    """Return the mnemonic string for ``wallets.<name>``, or None."""
    path = wallets_toml_path()
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    match = re.search(
        rf"\[wallets\.{re.escape(wallet_name)}\](.*?)(?=\n\[|\Z)",
        text,
        re.DOTALL,
    )
    if not match:
        return None
    mm = re.search(r'mnemonic\s*=\s*"([^"]+)"', match.group(1))
    if not mm:
        return None
    return mm.group(1).strip()
