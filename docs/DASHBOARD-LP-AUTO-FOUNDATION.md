# Dashboard LP + future foundation auto-LP

## User LP (dashboard — live)

Operators add Ston.fi liquidity from **Dashboard → Add liquidity**:

- **Top up existing LP** when `GET /v1/pools/by_market/{TON}/{minter}` finds a pool.
- **Start new pool** when no pool exists (`provisionType: Initial` via `@ston-fi/api`).
- User signs **two legs** (TON + jetton) via **TonConnect** — keys stay in Tonkeeper.
- On success, `POST /deployments/{id}/liquidity/confirm` sets `liquidity_added_at` in deployment metadata.

Web: `toolkit-staging/web/components/dashboard/add-liquidity-panel.tsx`  
API: `toolkit-staging/api/routes/deployments.py` → `liquidity/confirm`

## Foundation auto-LP (planned — not built)

Treasury sweep today runs `scripts/stonfi-add-liquidity.py` for the **25% LP slice** from toolkit TON payments:

| Step | Status |
|------|--------|
| Simulate balanced provision | Done |
| Queue `pending_broadcast` in `data/lp-pending.json` | Done |
| On-chain router broadcast (mirror `scripts/stonfi-swap/execute.mjs`) | **TODO** |
| Acton worker `/plx-treasury-sweep` endpoint | **TODO** (docs reference only) |

This path uses **ops wallets** (`plx-treasury`, Acton Tolk) — separate from user TonConnect LP.

When implementing auto-LP for tokens built via toolkit:

1. Reuse `simulateLiquidity` + router tx builder from web `lib/stonfi-liquidity.ts`.
2. Add optional post-deploy hook or cron keyed by `deployment_id` + minter.
3. Gate with env flags (`STONFI_LP_BROADCAST_ENABLED`, per-deployment opt-in).

See also [`LISTING-AUTOMATION.md`](LISTING-AUTOMATION.md) and [`FUNDRAISING-AND-LP-OPTIONS.md`](FUNDRAISING-AND-LP-OPTIONS.md).
