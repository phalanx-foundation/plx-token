#!/usr/bin/env python3
"""
Internal Acton HTTP worker - deploy client jettons + treasury sweep + sweep queue.

Run on Ubuntu (~/projects/plx-acton):
  ACTON_WORKER_TOKEN=... python3 scripts/acton-worker.py

Endpoints:
  POST /deploy                 - toolkit client jetton (toolkit-broadcast.sh)
  POST /treasury-sweep         - 25/25/25/25 treasury split (treasury-sweep.sh)
  POST /plx-treasury-sweep     - PLX jetton treasury split (plx-treasury-jetton-sweep.sh)
  POST /formation-quest-payout - single PLX jetton reward (formation-quest-payout.sh)
  POST /sweep-queue/enqueue    - append to data/sweep-pending.json (dedupe pending)
  GET  /health                 - liveness
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
TOKEN = os.environ.get("ACTON_WORKER_TOKEN", os.environ.get("ACTON_DEPLOY_TOKEN", "")).strip()
PORT = int(os.environ.get("ACTON_WORKER_PORT", "8787"))
HOST = os.environ.get("ACTON_WORKER_HOST", "127.0.0.1")
SWEEP_QUEUE_FILE = Path(
    os.environ.get("SWEEP_QUEUE_FILE", str(ROOT / "data" / "sweep-pending.json"))
)

def _run_script(script: str, params: dict[str, Any]) -> tuple[int, str, str]:
    env = os.environ.copy()
    for key, value in params.items():
        if value is not None:
            env[key] = str(value)
    proc = subprocess.run(
        ["bash", str(ROOT / "scripts" / script)],
        capture_output=True,
        text=True,
        timeout=int(os.environ.get("ACTON_DEPLOY_TIMEOUT_SEC", "300")),
        env=env,
        cwd=str(ROOT),
        check=False,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def _auth_ok(headers: Any) -> bool:
    if not TOKEN:
        return False
    auth = headers.get("Authorization", "")
    if auth == f"Bearer {TOKEN}":
        return True
    return headers.get("X-Acton-Token", "") == TOKEN


def _append_sweep_queue(entry: dict[str, Any]) -> dict[str, Any]:
    SWEEP_QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, Any]] = []
    if SWEEP_QUEUE_FILE.is_file():
        try:
            loaded = json.loads(SWEEP_QUEUE_FILE.read_text())
            if isinstance(loaded, list):
                entries = loaded
        except json.JSONDecodeError:
            entries = []

    deployment_id = str(entry.get("deployment_id", ""))
    for existing in entries:
        if (
            existing.get("deployment_id") == deployment_id
            and existing.get("status") == "pending"
        ):
            return {"queued": False, "reason": "already_pending", "queue_size": len(entries)}

    if not entry.get("queued_at"):
        entry["queued_at"] = datetime.now(tz=UTC).isoformat()
    if not entry.get("status"):
        entry["status"] = "pending"

    entries.append(entry)
    SWEEP_QUEUE_FILE.write_text(json.dumps(entries, indent=2))
    return {"queued": True, "queue_size": len(entries)}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def _json(self, code: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self._json(200, {"ok": True, "service": "acton-worker"})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        if not _auth_ok(self.headers):
            self._json(401, {"error": "unauthorized"})
            return

        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            params = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid json"})
            return
        if not isinstance(params, dict):
            self._json(400, {"error": "body must be object"})
            return

        if path == "/sweep-queue/enqueue":
            deployment_id = str(params.get("deployment_id", "")).strip()
            if not deployment_id:
                self._json(400, {"error": "deployment_id required"})
                return
            sweep_amount = params.get("sweep_amount_nano")
            if sweep_amount is None or int(sweep_amount) <= 0:
                self._json(400, {"error": "sweep_amount_nano must be positive integer"})
                return
            entry = dict(params)
            entry["deployment_id"] = deployment_id
            entry.setdefault("network", "mainnet")
            entry.setdefault("rail", "paypal")
            entry.setdefault("status", "pending")
            try:
                entry["sweep_amount_nano"] = int(entry["sweep_amount_nano"])
            except (TypeError, ValueError):
                self._json(400, {"error": "invalid sweep_amount_nano"})
                return
            self._json(200, _append_sweep_queue(entry))
            return

        if path == "/listing-automation":
            proc = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "plx-listing-automation.py")],
                capture_output=True,
                text=True,
                cwd=str(ROOT),
                env=os.environ.copy(),
                timeout=int(os.environ.get("LISTING_AUTOMATION_TIMEOUT_SEC", "300")),
                check=False,
            )
            try:
                payload = json.loads(proc.stdout) if proc.stdout.strip() else {}
            except json.JSONDecodeError:
                payload = {"stdout": proc.stdout[:500], "stderr": proc.stderr[:500]}
            self._json(200 if proc.returncode == 0 else 500, payload)
            return

        if path == "/deploy":
            script = "toolkit-broadcast.sh"
        elif path == "/treasury-sweep":
            script = "treasury-sweep.sh"
        elif path == "/plx-treasury-sweep":
            script = "plx-treasury-jetton-sweep.sh"
        elif path == "/formation-quest-payout":
            script = "formation-quest-payout.sh"
        else:
            self._json(404, {"error": "not found"})
            return

        code, stdout, stderr = _run_script(script, params)
        if code != 0:
            detail = stderr or stdout or "script failed"
            try:
                parsed = json.loads(detail)
                self._json(500, parsed)
            except json.JSONDecodeError:
                self._json(500, {"error": detail[:500]})
            return

        try:
            self._json(200, json.loads(stdout))
        except json.JSONDecodeError:
            self._json(500, {"error": "invalid script stdout", "stdout": stdout[:500]})


def main() -> None:
    if not TOKEN:
        raise SystemExit("Set ACTON_WORKER_TOKEN or ACTON_DEPLOY_TOKEN")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"acton-worker listening on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()

