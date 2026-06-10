# PLX listing automation (agent-run, not manual checklist)

Orchestrator: `scripts/plx-listing-automation.py`

## Enable locally / Acton server

```bash
# .env
LISTING_AUTOMATION_ENABLED=true
LISTING_QUEST_ENABLED=true          # post swap quest to Telegram
LISTING_PR_NUDGE_ENABLED=true       # comment on ton-assets PR #5540 if stale
LISTING_RUN_BRANDING=true           # run plx-branding-swap.py each cycle
TOKEN_TELEGRAM_BOT=...
TELEGRAM_OPS_CHAT_ID=...
LISTING_QUEST_CHAT_ID=...           # optional public channel
TONAPI_KEY=...                      # TonAPI verification probe
```

Cron (Ubuntu `~/projects/plx-acton`):

```cron
0 */6 * * * cd ~/projects/plx-acton && bash scripts/plx-listing-automation.sh >> logs/listing-automation.log 2>&1
```

GitHub Actions: `.github/workflows/listing-automation.yml` (every 6h + manual dispatch).

Acton worker: `POST /listing-automation` (Bearer `ACTON_WORKER_TOKEN`).

## What is fully automated

| Action | How |
|--------|-----|
| DexScreener pair health | API poll liquidity, price, txns |
| TonAPI `verification` | Poll jetton (needs `TONAPI_KEY`) |
| DYOR index check | `api.dyor.io/v1/jettons` |
| CoinGecko listed check | Search API |
| ton-assets PR status | `gh pr view 5540` + optional nudge comment |
| Telegram swap quest | Bot posts every 7d (configurable) |
| Ops summary | Telegram after each run |
| Branding micro-swap | Delegates to `plx-branding-swap.py` if enabled |
| State / logs | `data/listing-automation-state.json`, `data/listing-automation-log.json` |

## What platforms block full auto-submit

These have **no public listing API** — automation monitors and notifies; human or paid flow only:

| Platform | Why not 100% auto |
|----------|-------------------|
| Tonkeeper whitelist | Merge by Tonkeeper team (PR #5540) |
| Tonscan / Tonviewer labels | Web contact forms, no API |
| DYOR card update | Wallet-signed minter UI for external jettons |
| CoinGecko / CMC | Web forms + LP/volume gates (~$5k / ~$10k) |
| DexScreener enhanced profile | Paid “Update Token Info” (~$300 SOL) |
| tApps / TON Foundation | Application forms + demo video |

When LP crosses gates, automation marks `coingecko_ready` / `cmc_ready` in the run log and Telegram summary.

## Manual override

Force one run:

```bash
LISTING_AUTOMATION_ENABLED=true python3 scripts/plx-listing-automation.py
```

See also [`TOKEN-LISTING-INDEX-MATRIX.md`](TOKEN-LISTING-INDEX-MATRIX.md).
