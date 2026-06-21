#!/usr/bin/env python3
"""Process sweep-pending.json — retry PayPal treasury sweeps when balance is sufficient."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parent.parent
QUEUE = Path(os.environ.get("SWEEP_QUEUE_FILE", ROOT / "data" / "sweep-pending.json"))
SWEEP_SCRIPT = ROOT / "scripts" / "treasury-sweep.sh"
DEFAULT_OPS_CHAT_ID = "930979766"


def _tonapi_base(network: str) -> str:
    net = (network or "mainnet").strip().lower()
    if net == "mainnet":
        return os.environ.get("TONAPI_MAINNET_BASE", "https://tonapi.io/v2").rstrip("/")
    return os.environ.get("TONAPI_BASE", "https://testnet.tonapi.io/v2").rstrip("/")


def _treasury_address(network: str) -> str:
    net = (network or "mainnet").strip().lower()
    if net == "mainnet":
        return (
            os.environ.get("TON_TREASURY_ADDRESS_MAINNET", "")
            or os.environ.get("TON_TREASURY_ADDRESS", "")
        ).strip()
    return os.environ.get(
        "TON_TREASURY_ADDRESS",
        "kQCAfIuFFlS8RJyYQU7pFaN1XqcO8V4lZl-SH8Ca950XqGal",
    ).strip()


def _fetch_balance_nano(network: str) -> int:
    treasury = _treasury_address(network)
    if not treasury:
        return 0
    headers: dict[str, str] = {}
    api_key = os.environ.get("TONAPI_KEY", "").strip()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    url = f"{_tonapi_base(network)}/accounts/{treasury}"
    with httpx.Client(timeout=20.0) as client:
        res = client.get(url, headers=headers or None)
    if res.status_code != 200:
        return 0
    data = res.json()
    return int(data.get("balance", 0)) if isinstance(data, dict) else 0


def _send_telegram(text: str) -> bool:
    token = os.environ.get("TOKEN_TELEGRAM_BOT", "").strip()
    chat_id = os.environ.get("TELEGRAM_OPS_CHAT_ID", DEFAULT_OPS_CHAT_ID).strip()
    if not token or not chat_id:
        return False
    try:
        with httpx.Client(timeout=15.0) as client:
            res = client.post(
                f"https://api.telegram.org/bot{token}/sendMessage",
                json={"chat_id": chat_id, "text": text[:4096]},
            )
        return res.status_code == 200
    except httpx.HTTPError:
        return False


def _post_callback(deployment_id: str, result: dict) -> bool:
    url = os.environ.get("TOOLKIT_SWEEP_CALLBACK_URL", "").strip()
    token = os.environ.get("ACTON_DEPLOY_TOKEN", "").strip()
    if not url or not token:
        return False
    payload = {
        "deployment_id": deployment_id,
        "sweep_tx_hashes": result.get("sweep_tx_hashes"),
        "treasury_sweep_completed_at": datetime.now(tz=UTC).isoformat(),
        "treasury_sweep_amount_nano": result.get("sweep_amount_nano"),
        "treasury_sweep_quarter_nano": result.get("quarter_nano"),
        "treasury_sweep_buyback_nano": result.get("buyback_nano"),
        "treasury_sweep_trigger": "sweep_queue_cron",
        "treasury_sweep_lp": result.get("lp_slice"),
    }
    try:
        with httpx.Client(timeout=30.0) as client:
            res = client.post(
                url,
                json=payload,
                headers={"Authorization": f"Bearer {token}"},
            )
        return res.status_code == 200
    except httpx.HTTPError:
        return False


def _run_sweep(entry: dict) -> dict | None:
    network = str(entry.get("network", "mainnet"))
    env = os.environ.copy()
    env["network"] = network
    env["DEPLOYMENT_ID"] = str(entry.get("deployment_id", "unknown"))
    env["SWEEP_AMOUNT_NANO"] = str(entry.get("sweep_amount_nano", 0))
    proc = subprocess.run(
        ["bash", str(SWEEP_SCRIPT)],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        return None
    try:
        parsed = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def main() -> int:
    if not QUEUE.exists():
        print(json.dumps({"processed": 0, "queue_size": 0}))
        return 0

    entries = json.loads(QUEUE.read_text())
    if not isinstance(entries, list):
        print(json.dumps({"processed": 0, "error": "invalid_queue"}))
        return 1

    processed = 0
    changed = False
    for i, entry in enumerate(entries):
        if entry.get("status") != "pending":
            continue

        network = str(entry.get("network", "mainnet"))
        amount = int(entry.get("sweep_amount_nano", 0))
        if amount <= 0:
            continue

        balance = _fetch_balance_nano(network)
        if balance < amount:
            continue

        result = _run_sweep(entry)
        if not result:
            entries[i]["last_attempt_at"] = datetime.now(tz=UTC).isoformat()
            changed = True
            continue

        deployment_id = str(entry.get("deployment_id", "unknown"))
        entries[i]["status"] = "processed"
        entries[i]["processed_at"] = datetime.now(tz=UTC).isoformat()
        entries[i]["result"] = result
        changed = True
        processed += 1

        _post_callback(deployment_id, result)
        sweep_ton = amount / 1_000_000_000
        hashes = result.get("sweep_tx_hashes") or []
        hash_line = f"\ntx: {', '.join(hashes[:3])}" if hashes else ""
        _send_telegram(
            f"Treasury sweep completed (queue)\n"
            f"deployment: {deployment_id}\n"
            f"amount: {sweep_ton:.4f} TON{hash_line}"
        )

    if changed:
        QUEUE.write_text(json.dumps(entries, indent=2))

    print(json.dumps({"processed": processed, "queue_size": len(entries)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
