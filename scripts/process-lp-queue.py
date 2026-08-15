#!/usr/bin/env python3
"""Retry LP queue entries when STONFI_POOL_ADDRESS becomes available."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = Path(os.environ.get("LP_QUEUE_FILE", ROOT / "data" / "lp-pending.json"))


def main() -> int:
    if not QUEUE.exists():
        print(json.dumps({"processed": 0}))
        return 0

    entries = json.loads(QUEUE.read_text())
    if not isinstance(entries, list):
        return 0

    changed = False
    for i, entry in enumerate(entries):
        if entry.get("status") not in {"waiting_pool", "pending_broadcast"}:
            continue
        env = os.environ.copy()
        env["LP_TON_NANO"] = str(entry.get("ton_nano", 0))
        env["network"] = str(entry.get("network", "mainnet"))
        env["DEPLOYMENT_ID"] = str(entry.get("deployment_id", "retry"))
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "stonfi-add-liquidity.py")],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            env=env,
            check=False,
        )
        if proc.returncode != 0:
            continue
        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError:
            continue
        if result.get("mode") != "fallback_no_pool":
            entries[i]["status"] = "processed"
            entries[i]["result"] = result
            changed = True

    if changed:
        QUEUE.write_text(json.dumps(entries, indent=2))
    print(json.dumps({"processed": changed, "queue_size": len(entries)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
