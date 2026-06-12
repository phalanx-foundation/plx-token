#!/usr/bin/env python3
"""
Pioneer Season PLX batch transfers from plx-community wallet.

Queue file: data/airdrop-season-queue.json
  [{"address":"EQ...","amount_plx":"1500","season":1,"quest_id":"swap-001"}]

Dry-run:  DRY_RUN=1 python3 scripts/airdrop-season-batch.py
Limit:    AIRDROP_BATCH_LIMIT=20 (default)

Requires Acton on PATH + wallets.toml with plx-community-mainnet on deploy server.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = Path(os.environ.get("AIRDROP_QUEUE", ROOT / "data" / "airdrop-season-queue.json"))
NET = os.environ.get("ACTON_NETWORK", "mainnet")
FROM_WALLET = os.environ.get("AIRDROP_FROM_WALLET", "plx-community")
MINTER = os.environ.get(
    "PLX_JETTON_MINTER_MAINNET",
    "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS",
)
LIMIT = int(os.environ.get("AIRDROP_BATCH_LIMIT", "20"))
LOG = Path(os.environ.get("AIRDROP_LOG", ROOT / "data" / "airdrop-season-log.json"))


def _load_queue() -> list[dict]:
    if not QUEUE.exists():
        return []
    raw = json.loads(QUEUE.read_text())
    return raw if isinstance(raw, list) else []


def _save_queue(items: list[dict]) -> None:
    QUEUE.parent.mkdir(parents=True, exist_ok=True)
    QUEUE.write_text(json.dumps(items, indent=2) + "\n")


def _append_log(entry: dict) -> None:
    logs: list = []
    if LOG.exists():
        try:
            logs = json.loads(LOG.read_text())
        except json.JSONDecodeError:
            logs = []
    if not isinstance(logs, list):
        logs = []
    logs.append(entry)
    LOG.write_text(json.dumps(logs[-500:], indent=2) + "\n")


def _transfer_one(recipient: str, amount_plx: str) -> dict:
    env = os.environ.copy()
    env["JETTON_SENDER"] = FROM_WALLET
    env["JETTON_TRANSFER_RECIPIENT"] = recipient
    env["JETTON_TRANSFER_AMOUNT"] = amount_plx
    proc = subprocess.run(
        ["acton", "script", "scripts/transfer.tolk", "--net", NET],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    return {
        "ok": proc.returncode == 0,
        "stdout": (proc.stdout or "")[-800:],
        "stderr": (proc.stderr or "")[-400:],
    }


def main() -> int:
    queue = _load_queue()
    pending = [q for q in queue if q.get("status") != "sent"]
    if not pending:
        print("No pending airdrop entries.")
        return 0

    batch = pending[:LIMIT]
    print(f"Pioneer batch: {len(batch)} of {len(pending)} pending (minter={MINTER})")

    if os.environ.get("DRY_RUN") == "1":
        for item in batch:
            print(f"  DRY_RUN send {item.get('amount_plx')} PLX -> {item.get('address')}")
        return 0

    sent_ids: set[str] = set()
    for item in batch:
        addr = (item.get("address") or "").strip()
        amt = str(item.get("amount_plx") or "").strip()
        if not addr or not amt:
            item["status"] = "error"
            item["error"] = "missing address or amount"
            continue
        result = _transfer_one(addr, amt)
        item["status"] = "sent" if result["ok"] else "error"
        item["result"] = result
        if result["ok"]:
            sent_ids.add(item.get("id") or addr)
        _append_log({"item": item, "at": __import__("datetime").datetime.utcnow().isoformat() + "Z"})

    for q in queue:
        if q.get("id") in sent_ids or (q.get("address") in sent_ids and q.get("status") == "sent"):
            q["status"] = "sent"

    _save_queue(queue)
    ok = sum(1 for i in batch if i.get("status") == "sent")
    print(f"Sent {ok}/{len(batch)}")
    return 0 if ok == len(batch) else 1


if __name__ == "__main__":
    sys.exit(main())
