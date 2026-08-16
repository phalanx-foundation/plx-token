"""Multi-token listing configuration — canonical fields for ton-assets, TonAPI, DexScreener automation."""

from __future__ import annotations

from dataclasses import dataclass, field

from lib.plx_logo_ipfs import plx_listing_logo_url

TON_ASSETS_REPO = "tonkeeper/ton-assets"

COINGECKO_MIN_LP_USD = int(__import__("os").environ.get("LISTING_COINGECKO_MIN_LP_USD", "5000"))
CMC_MIN_LP_USD = int(__import__("os").environ.get("LISTING_CMC_MIN_LP_USD", "10000"))

TONAPI_MIN_HOLDERS = int(__import__("os").environ.get("TONAPI_MIN_HOLDERS", "100"))
TONAPI_MIN_TON_RESERVE = float(__import__("os").environ.get("TONAPI_MIN_TON_RESERVE", "100"))


@dataclass
class TokenListingConfig:
    """Per-token listing configuration — minter, pool, PR, logo, links, description.

    Passed to every checker/monitor function so a single script can probe
    any token without hardcoding PLX constants.
    """

    name: str
    symbol: str
    minter_address: str
    description: str = ""
    logo_url: str = ""
    decimals: int = 9
    pool_address: str = ""
    github_repo_url: str = ""
    site_url: str = ""
    token_page_url: str = ""
    social_links: list[str] = field(default_factory=list)
    ton_assets_pr: int | None = None

    # derived URLs
    @property
    def pool_url(self) -> str:
        return f"https://app.ston.fi/pools/{self.pool_address}" if self.pool_address else ""

    @property
    def dexscreener_url(self) -> str:
        return f"https://dexscreener.com/ton/{self.pool_address.lower()}" if self.pool_address else ""

    @property
    def tonviewer_url(self) -> str:
        return f"https://tonviewer.com/{self.minter_address}" if self.minter_address else ""

    def quest_message(self) -> str:
        parts = [
            f"{self.symbol} mainnet swap quest (builders)\n",
        ]
        if self.pool_url:
            parts.append(f"1. Ston.fi pool: {self.pool_url}\n")
        parts.append(f"2. Swap >= 0.05 TON -> {self.symbol} (minter: {self.minter_address})\n")
        parts.append("3. Reply with Tonviewer tx link.\n")
        if self.token_page_url:
            parts.append(f"Site: {self.token_page_url}\n")
        parts.append("Utility token — Phalanx Toolkit. Not investment advice.")
        return "\n".join(parts)


# -- PLX canonical (backward compatible) ---------------------------------------------------

PLX_MINTER = "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
PLX_STONFI_POOL = "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq"
PLX_TON_ASSETS_PR = 5540

_PLX = TokenListingConfig(
    name="Phalanx",
    symbol="PLX",
    minter_address=PLX_MINTER,
    pool_address=PLX_STONFI_POOL,
    description=(
        "PLX is the utility jetton of Phalanx Foundation — audited Tolk JettonMinter on TON. "
        "Fixed 1B supply; toolkit payments burn 50% on receipt. Live PLX/TON pool on Ston.fi."
    ),
    logo_url=plx_listing_logo_url(),
    github_repo_url="https://github.com/phalanx-foundation/plx-token",
    site_url="https://plx.foundation",
    token_page_url="https://plx.foundation/plx-token",
    social_links=[
        "https://t.me/phalanxfoundation",
        "https://t.me/phalanxfoundationbot",
        "https://github.com/phalanx-foundation/plx-token",
    ],
    ton_assets_pr=PLX_TON_ASSETS_PR,
)

# Backward-compat aliases (existing PLX-only scripts keep working)
STONFI_POOL = PLX_STONFI_POOL
TON_ASSETS_PR = PLX_TON_ASSETS_PR
SITE = _PLX.site_url
TOKEN_PAGE = _PLX.token_page_url
LOGO = _PLX.logo_url
GITHUB = _PLX.github_repo_url
STONFI_POOL_URL = _PLX.pool_url
DEXSCREENER_PAIR_URL = _PLX.dexscreener_url
TONVIEWER_MINTER = _PLX.tonviewer_url
DESCRIPTION = _PLX.description
QUEST_MESSAGE = _PLX.quest_message()


def plx_config() -> TokenListingConfig:
    return _PLX


def config_from_kwargs(**kwargs: str | int | list[str] | None) -> TokenListingConfig:
    """Build a TokenListingConfig from keyword arguments (e.g. from a deployed-token DB row)."""
    cfg_args = {k: v for k, v in kwargs.items() if v is not None}
    social_raw = cfg_args.pop("social_links", None) or []
    if isinstance(social_raw, str):
        social_links = [s.strip() for s in social_raw.split(",") if s.strip()]
    else:
        social_links = list(social_raw)
    return TokenListingConfig(
        **{k: v for k, v in cfg_args.items() if k in TokenListingConfig.__dataclass_fields__},
        social_links=social_links,
    )
