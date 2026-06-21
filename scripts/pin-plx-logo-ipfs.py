#!/usr/bin/env python3
"""Pin PLX logo to IPFS via Pinata and update metadata/plx-logo-ipfs.json."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx

REPO_ROOT = Path(__file__).resolve().parents[1]
LOGO_PATH = REPO_ROOT / "toolkit-staging" / "web" / "public" / "plx-logo.png"
METADATA_PATH = REPO_ROOT / "metadata" / "plx-logo-ipfs.json"
PINATA_UPLOAD_URL = "https://uploads.pinata.cloud/v3/files"


def _gateway_host() -> str:
    return os.environ.get("IPFS_GATEWAY_HOST", "ipfs.plx.foundation").strip()


def main() -> int:
    jwt = os.environ.get("PINATA_JWT", "").strip()
    if not jwt:
        print("PINATA_JWT not set — load .env first", file=sys.stderr)
        return 1
    if not LOGO_PATH.is_file():
        print(f"Logo missing: {LOGO_PATH}", file=sys.stderr)
        return 1

    content = LOGO_PATH.read_bytes()
    headers = {"Authorization": f"Bearer {jwt}"}
    files = {"file": ("plx-logo.png", content, "image/png")}
    data = {"network": "public", "name": "plx-logo.png"}

    with httpx.Client(timeout=60.0) as client:
        res = client.post(PINATA_UPLOAD_URL, headers=headers, files=files, data=data)

    if res.status_code not in {200, 201}:
        print(f"Pinata failed HTTP {res.status_code}: {res.text[:400]}", file=sys.stderr)
        return 1

    payload = res.json()
    cid = (payload.get("cid") or payload.get("IpfsHash") or "").strip()
    if not cid:
        print("Pinata response missing cid", file=sys.stderr)
        return 1

    host = _gateway_host()
    record = {
        "cid": cid,
        "ipfs_uri": f"ipfs://{cid}",
        "gateway_url": f"https://{host}/ipfs/{cid}",
        "legacy_https_url": "https://plx.foundation/plx-logo.png",
        "gateway_host": host,
        "pinned_at": datetime.now(tz=timezone.utc).isoformat(),
        "source_file": "toolkit-staging/web/public/plx-logo.png",
    }
    METADATA_PATH.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    print(json.dumps(record, indent=2))
    print("\nNext: set JETTON_IMAGE=ipfs://" + cid + " and run refresh-metadata / change-metadata")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
