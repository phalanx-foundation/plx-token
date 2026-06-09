#!/usr/bin/env python3
"""Print pending swap queue + manual Ston.fi URLs."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from lib.stonfi_swap import load_swap_queue, stonfi_pool_url  # noqa: E402


def main() -> int:
    entries = load_swap_queue()
    pending = [e for e in entries if e.get("status") in ("simulated", "queued_manual", "broadcast_failed")]
    print(json.dumps({"pool_url": stonfi_pool_url(), "pending": pending, "count": len(pending)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
