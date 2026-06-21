"""Canonical PLX listing fields for automation."""

from __future__ import annotations

from lib.plx_logo_ipfs import plx_listing_logo_url

PLX_MINTER = "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
STONFI_POOL = "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq"
TON_ASSETS_PR = 5540
TON_ASSETS_REPO = "tonkeeper/ton-assets"

SITE = "https://plx.foundation"
TOKEN_PAGE = "https://plx.foundation/plx-token"
LOGO = plx_listing_logo_url()
GITHUB = "https://github.com/phalanx-foundation/plx-token"
STONFI_POOL_URL = f"https://app.ston.fi/pools/{STONFI_POOL}"
DEXSCREENER_PAIR_URL = f"https://dexscreener.com/ton/{STONFI_POOL.lower()}"
TONVIEWER_MINTER = f"https://tonviewer.com/{PLX_MINTER}"

DESCRIPTION = (
    "PLX is the utility jetton of Phalanx Foundation — audited Tolk JettonMinter on TON. "
    "Fixed 1B supply; toolkit payments burn 50% on receipt. Live PLX/TON pool on Ston.fi."
)

COINGECKO_MIN_LP_USD = int(__import__("os").environ.get("LISTING_COINGECKO_MIN_LP_USD", "5000"))
CMC_MIN_LP_USD = int(__import__("os").environ.get("LISTING_CMC_MIN_LP_USD", "10000"))

QUEST_MESSAGE = (
    "PLX mainnet swap quest (builders)\n\n"
    f"1. Ston.fi pool: {STONFI_POOL_URL}\n\n"
    f"2. Swap ≥ 0.05 TON → PLX (minter: {PLX_MINTER})\n\n"
    f"3. Reply with Tonviewer tx link.\n\n"
    f"Site: {TOKEN_PAGE}\n"
    "Utility token — Phalanx Toolkit. Not investment advice."
)
