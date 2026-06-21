#!/usr/bin/env python3
"""
PLX market dashboard — DexScreener + Ston.fi pool stats + recent swaps.

Usage:
  python3 scripts/plx-dex-dashboard.py              # print summary
  python3 scripts/plx-dex-dashboard.py --write        # data/market-snapshot.json + docs/plx-market-dashboard.html
  python3 scripts/plx-dex-dashboard.py --serve      # local preview on :8765

Cron (Ubuntu acton server, every 15 min):
  */15 * * * * cd ~/projects/plx-acton && python3 scripts/plx-dex-dashboard.py --write
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_PATH = Path(os.environ.get("PLX_MARKET_SNAPSHOT", ROOT / "data" / "market-snapshot.json"))
HTML_PATH = Path(os.environ.get("PLX_MARKET_HTML", ROOT / "docs" / "plx-market-dashboard.html"))
STONFI_API = os.environ.get("STONFI_API_BASE", "https://api.ston.fi").rstrip("/")
DEXSCREENER_API = "https://api.dexscreener.com/latest/dex/pairs/ton"
UA = {"User-Agent": "PLX-Dashboard/1.0 (phalanx-foundation/plx-token)"}
BLOCKS_PER_DAY = 17280  # ~5s per TON block
EVENT_CHUNK = int(os.environ.get("PLX_MARKET_EVENT_CHUNK", "1000"))

DEFAULT_POOL = "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq"
DEFAULT_MINTER = "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"


def _pool_address() -> str:
    return os.environ.get("STONFI_POOL_ADDRESS", DEFAULT_POOL).strip()


def _minter_address() -> str:
    return os.environ.get(
        "PLX_JETTON_MINTER_MAINNET",
        os.environ.get("JETTON_MINTER_ADDRESS", DEFAULT_MINTER),
    ).strip()


def _fetch_json(url: str, timeout: int = 45) -> dict | list:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read().decode())


def fetch_dexscreener(pool: str) -> dict | None:
    try:
        data = _fetch_json(f"{DEXSCREENER_API}/{pool}")
        pair = data.get("pair") or (data.get("pairs") or [None])[0]
        return pair if isinstance(pair, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, KeyError):
        return None


def fetch_stonfi_pool(pool: str) -> dict | None:
    try:
        data = _fetch_json(f"{STONFI_API}/v1/pools/{pool}")
        return data.get("pool") if isinstance(data, dict) else None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def _latest_block() -> int:
    data = _fetch_json(f"{STONFI_API}/v1/screener/latest-block")
    return int(data["block"]["blockNumber"])


def fetch_pool_swaps(pool: str, blocks_back: int = BLOCKS_PER_DAY) -> list[dict]:
    """Recent swap events for this pool via Ston.fi dexscreener export API (chunked)."""
    latest = _latest_block()
    start = max(0, latest - blocks_back)
    swaps: list[dict] = []
    cursor = start
    while cursor < latest:
        end = min(cursor + EVENT_CHUNK, latest)
        url = f"{STONFI_API}/export/dexscreener/v1/events?fromBlock={cursor}&toBlock={end}"
        try:
            data = _fetch_json(url)
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
            cursor = end + 1
            continue
        for ev in data.get("events", []):
            if ev.get("eventType") != "swap" or ev.get("pairId") != pool:
                continue
            swaps.append(normalize_swap(ev))
        cursor = end + 1
    swaps.sort(key=lambda s: s.get("block_number", 0), reverse=True)
    return swaps


def normalize_swap(ev: dict) -> dict:
    """PLX is token0, TON is token1 in our pool."""
    side = "unknown"
    plx_amount = ""
    ton_amount = ""
    if ev.get("amount1In") and ev.get("amount0Out"):
        side = "buy"
        ton_amount = ev.get("amount1In", "")
        plx_amount = ev.get("amount0Out", "")
    elif ev.get("amount0In") and ev.get("amount1Out"):
        side = "sell"
        plx_amount = ev.get("amount0In", "")
        ton_amount = ev.get("amount1Out", "")
    elif ev.get("amount1In") and ev.get("amount1Out"):
        side = "buy"
        ton_amount = ev.get("amount1In", "")
    elif ev.get("amount0In") and ev.get("amount0Out"):
        side = "sell"
        plx_amount = ev.get("amount0In", "")

    block = ev.get("block") or {}
    return {
        "txn_id": ev.get("txnId", ""),
        "side": side,
        "plx_amount": plx_amount,
        "ton_amount": ton_amount,
        "price_native": ev.get("priceNative", ""),
        "maker": ev.get("maker", ""),
        "block_number": block.get("blockNumber"),
        "block_timestamp": block.get("blockTimestamp"),
        "tonviewer": f"https://tonviewer.com/transaction/{ev.get('txnId', '')}",
    }


def build_snapshot(pool: str, minter: str) -> dict:
    dex = fetch_dexscreener(pool)
    ston = fetch_stonfi_pool(pool)
    swaps = fetch_pool_swaps(pool)

    reserve_plx = ""
    reserve_ton = ""
    if ston:
        reserve_plx = ston.get("reserve0", "")
        reserve_ton = ston.get("reserve1", "")

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "pool_address": pool,
        "minter_address": minter,
        "dexscreener_url": f"https://dexscreener.com/ton/{pool.lower()}",
        "stonfi_pool_url": f"https://app.ston.fi/pools/{pool}",
        "tonviewer_pool_url": f"https://tonviewer.com/{pool}",
        "price": {
            "ton_per_plx": dex.get("priceNative") if dex else None,
            "usd_per_plx": dex.get("priceUsd") if dex else None,
            "fdv_usd": dex.get("fdv") if dex else None,
            "liquidity_usd": (dex.get("liquidity") or {}).get("usd") if dex else None,
        },
        "volume_usd": (dex.get("volume") or {}) if dex else {},
        "txns": (dex.get("txns") or {}) if dex else {},
        "price_change_pct": (dex.get("priceChange") or {}) if dex else {},
        "reserves": {
            "plx": reserve_plx,
            "ton": reserve_ton,
            "plx_human": _nano_to_float(reserve_plx, 9),
            "ton_human": _nano_to_float(reserve_ton, 9),
        },
        "recent_swaps": swaps[:50],
        "swap_count_24h": len(swaps),
    }


def _nano_to_float(raw: str, decimals: int) -> float | None:
    if not raw:
        return None
    try:
        return float(raw) / (10 ** decimals)
    except ValueError:
        try:
            return float(raw)
        except ValueError:
            return None


def print_summary(snap: dict) -> None:
    p = snap["price"]
    tx = snap.get("txns", {}).get("h24", {})
    vol = snap.get("volume_usd", {}).get("h24")
    print(f"PLX market @ {snap['generated_at']}")
    print(f"  Price: {p.get('ton_per_plx')} TON / ${p.get('usd_per_plx')} USD")
    print(f"  FDV: ${p.get('fdv_usd')} | Liquidity: ${p.get('liquidity_usd')}")
    print(f"  24h volume: ${vol} | 24h txns: {tx.get('buys', 0)} buys, {tx.get('sells', 0)} sells")
    print(f"  Pool swaps (24h scan): {snap.get('swap_count_24h', 0)}")
    if snap.get("recent_swaps"):
        s = snap["recent_swaps"][0]
        print(f"  Latest swap: {s.get('side')} | PLX {s.get('plx_amount')} | TON {s.get('ton_amount')}")
    print(f"  Dashboard: file://{HTML_PATH}")


def write_html(snap: dict) -> None:
    payload = json.dumps(snap, indent=2)
    pool = snap["pool_address"]
    embed = f"https://dexscreener.com/ton/{pool.lower()}?embed=1&theme=dark&trades=1&info=0"
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>PLX Market Dashboard</title>
  <style>
    :root {{
      --bg: #0b0f14;
      --card: #121820;
      --border: #1e2a38;
      --text: #e8eef5;
      --muted: #8b9bb4;
      --accent: #3d9eff;
      --buy: #22c55e;
      --sell: #ef4444;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, Segoe UI, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
    }}
    header {{
      padding: 1.25rem 1.5rem;
      border-bottom: 1px solid var(--border);
      display: flex;
      flex-wrap: wrap;
      gap: 1rem;
      align-items: center;
      justify-content: space-between;
    }}
    h1 {{ margin: 0; font-size: 1.25rem; }}
    .links a {{
      color: var(--accent);
      margin-right: 1rem;
      text-decoration: none;
    }}
    .links a:hover {{ text-decoration: underline; }}
    main {{ padding: 1rem 1.5rem 2rem; max-width: 1200px; margin: 0 auto; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 0.75rem;
      margin-bottom: 1rem;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 0.85rem 1rem;
    }}
    .card .label {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; }}
    .card .value {{ font-size: 1.15rem; font-weight: 600; margin-top: 0.25rem; }}
    .chart-wrap {{
      border: 1px solid var(--border);
      border-radius: 10px;
      overflow: hidden;
      margin-bottom: 1rem;
      background: var(--card);
    }}
    iframe {{ width: 100%; height: 480px; border: 0; display: block; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
    }}
    th, td {{
      padding: 0.55rem 0.65rem;
      border-bottom: 1px solid var(--border);
      text-align: left;
    }}
    th {{ color: var(--muted); font-weight: 500; }}
    .side-buy {{ color: var(--buy); }}
    .side-sell {{ color: var(--sell); }}
    .muted {{ color: var(--muted); font-size: 0.8rem; }}
    .refresh {{ color: var(--muted); font-size: 0.8rem; }}
  </style>
</head>
<body>
  <header>
    <h1>PLX / TON — Phalanx Market</h1>
    <div class="links">
      <a href="{snap['dexscreener_url']}" target="_blank" rel="noopener">DexScreener</a>
      <a href="{snap['stonfi_pool_url']}" target="_blank" rel="noopener">Ston.fi Pool</a>
      <a href="{snap['tonviewer_pool_url']}" target="_blank" rel="noopener">Tonviewer</a>
    </div>
  </header>
  <main>
    <p class="refresh" id="meta">Loading…</p>
    <div class="grid" id="stats"></div>
    <div class="chart-wrap">
      <iframe src="{embed}" title="PLX chart"></iframe>
    </div>
    <h2>Recent swaps (pool)</h2>
    <p class="muted">Buy = someone spent TON to receive PLX. Sell = someone sold PLX for TON.</p>
    <div class="card" style="padding:0; overflow:hidden;">
      <table>
        <thead>
          <tr>
            <th>Side</th>
            <th>PLX</th>
            <th>TON</th>
            <th>Maker</th>
            <th>Tx</th>
          </tr>
        </thead>
        <tbody id="swaps"></tbody>
      </table>
    </div>
  </main>
  <script id="snapshot" type="application/json">{payload}</script>
  <script>
    const POOL = "{pool}";
    const DEX_URL = "https://api.dexscreener.com/latest/dex/pairs/ton/" + POOL;

    function fmtUsd(n) {{
      if (n == null) return "—";
      const x = Number(n);
      if (Number.isNaN(x)) return n;
      if (x < 0.01) return "$" + x.toFixed(6);
      return "$" + x.toLocaleString(undefined, {{ maximumFractionDigits: 2 }});
    }}

    function card(label, value) {{
      return `<div class="card"><div class="label">${{label}}</div><div class="value">${{value}}</div></div>`;
    }}

    function renderStats(snap, live) {{
      const p = live?.priceNative ? live : null;
      const priceTon = p?.priceNative ?? snap.price?.ton_per_plx ?? "—";
      const priceUsd = p?.priceUsd ?? snap.price?.usd_per_plx ?? "—";
      const fdv = p?.fdv ?? snap.price?.fdv_usd;
      const liq = p?.liquidity?.usd ?? snap.price?.liquidity_usd;
      const vol = p?.volume?.h24 ?? snap.volume_usd?.h24;
      const buys = p?.txns?.h24?.buys ?? snap.txns?.h24?.buys ?? 0;
      const sells = p?.txns?.h24?.sells ?? snap.txns?.h24?.sells ?? 0;
      const chg = p?.priceChange?.h24 ?? snap.price_change_pct?.h24;

      document.getElementById("stats").innerHTML = [
        card("Price (TON)", priceTon),
        card("Price (USD)", fmtUsd(priceUsd)),
        card("FDV", fmtUsd(fdv)),
        card("Liquidity", fmtUsd(liq)),
        card("24h Volume", fmtUsd(vol)),
        card("24h Buys / Sells", `${{buys}} / ${{sells}}`),
        card("24h Change", chg != null ? `${{Number(chg).toFixed(2)}}%` : "—"),
        card("Pool swaps (24h)", snap.swap_count_24h ?? "—"),
      ].join("");
    }}

    function renderSwaps(swaps) {{
      const rows = (swaps || []).map(s => {{
        const side = s.side || "?";
        const cls = side === "buy" ? "side-buy" : side === "sell" ? "side-sell" : "";
        const shortMaker = s.maker ? s.maker.slice(0, 6) + "…" + s.maker.slice(-4) : "—";
        const tx = s.txn_id ? `<a href="${{s.tonviewer}}" target="_blank" rel="noopener">${{s.txn_id.slice(0, 10)}}…</a>` : "—";
        return `<tr><td class="${{cls}}">${{side}}</td><td>${{s.plx_amount || "—"}}</td><td>${{s.ton_amount || "—"}}</td><td class="muted">${{shortMaker}}</td><td>${{tx}}</td></tr>`;
      }}).join("");
      document.getElementById("swaps").innerHTML = rows || "<tr><td colspan=5 class=muted>No swaps in last 24h window</td></tr>";
    }}

    async function refresh() {{
      const snap = JSON.parse(document.getElementById("snapshot").textContent);
      let live = null;
      try {{
        const r = await fetch(DEX_URL);
        const j = await r.json();
        live = j.pair || (j.pairs && j.pairs[0]);
      }} catch (_) {{}}
      renderStats(snap, live);
      renderSwaps(snap.recent_swaps);
      document.getElementById("meta").textContent =
        `Snapshot: ${{snap.generated_at}} · Live refresh: ${{new Date().toISOString()}} · Run: python3 scripts/plx-dex-dashboard.py --write`;
    }}

    refresh();
    setInterval(refresh, 60000);
  </script>
</body>
</html>
"""
    HTML_PATH.parent.mkdir(parents=True, exist_ok=True)
    HTML_PATH.write_text(html, encoding="utf-8")


def write_snapshot(snap: dict) -> None:
    SNAPSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT_PATH.write_text(json.dumps(snap, indent=2) + "\n", encoding="utf-8")


def serve(port: int) -> None:
    os.chdir(ROOT)
    handler = SimpleHTTPRequestHandler
    httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"Serving {ROOT} at http://127.0.0.1:{port}/docs/plx-market-dashboard.html")
    httpd.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser(description="PLX DEX market dashboard")
    parser.add_argument("--write", action="store_true", help="Write JSON snapshot + HTML")
    parser.add_argument("--serve", action="store_true", help="Serve repo root for local preview")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    pool = _pool_address()
    minter = _minter_address()
    snap = build_snapshot(pool, minter)

    if args.write:
        write_snapshot(snap)
        write_html(snap)
        print(f"Wrote {SNAPSHOT_PATH}")
        print(f"Wrote {HTML_PATH}")

    print_summary(snap)

    if args.serve:
        serve(args.port)

    return 0


if __name__ == "__main__":
    sys.exit(main())
