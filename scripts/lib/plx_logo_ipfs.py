"""Shared PLX logo URLs — IPFS gateway with HTTPS fallback."""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_METADATA_FILE = _REPO_ROOT / "metadata" / "plx-logo-ipfs.json"
_LEGACY_LOGO = "https://plx.foundation/plx-logo.png"


@lru_cache(maxsize=1)
def _load_record() -> dict:
    if not _METADATA_FILE.is_file():
        return {}
    try:
        parsed = json.loads(_METADATA_FILE.read_text(encoding="utf-8"))
        return parsed if isinstance(parsed, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def plx_logo_cid() -> str:
    env_cid = os.environ.get("PLX_LOGO_IPFS_CID", "").strip()
    if env_cid:
        return env_cid
    record = _load_record()
    cid = record.get("cid")
    return cid.strip() if isinstance(cid, str) else ""


def plx_logo_gateway_host() -> str:
    return (
        os.environ.get("IPFS_GATEWAY_HOST", "").strip()
        or _load_record().get("gateway_host")
        or "ipfs.plx.foundation"
    )


def plx_logo_gateway_url() -> str:
    env_url = os.environ.get("PLX_LOGO_GATEWAY_URL", "").strip()
    if env_url.startswith("https://"):
        return env_url

    record = _load_record()
    stored = record.get("gateway_url")
    if isinstance(stored, str) and stored.startswith("https://"):
        return stored

    cid = plx_logo_cid()
    if cid:
        return f"https://{plx_logo_gateway_host()}/ipfs/{cid}"

    return _LEGACY_LOGO


def plx_logo_ipfs_uri() -> str:
    env_uri = os.environ.get("PLX_LOGO_IPFS_URI", "").strip()
    if env_uri.startswith("ipfs://"):
        return env_uri

    record = _load_record()
    stored = record.get("ipfs_uri")
    if isinstance(stored, str) and stored.startswith("ipfs://"):
        return stored

    cid = plx_logo_cid()
    return f"ipfs://{cid}" if cid else ""


def plx_listing_logo_url() -> str:
    """HTTPS URL for listings that require https:// (Tonkeeper, CoinGecko, etc.)."""
    return plx_logo_gateway_url()
