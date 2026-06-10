# PLX token listing & index matrix

Single checklist for **Phalanx (PLX)** discoverability after mainnet LP. Update status as submissions complete.

**Minter:** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`  
**Ston.fi pool:** `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq`  
**Site:** https://plx.foundation/plx-token  
**Logo:** https://plx.foundation/plx-logo.png  
**GitHub:** https://github.com/phalanx-foundation/plx-token

---

## Tier A — TON wallet & DEX (do first)

| # | Platform | Submit URL | Gate | Status | Evidence |
|---|----------|------------|------|--------|----------|
| A1 | Tonkeeper ton-assets | https://github.com/tonkeeper/ton-assets/pull/5540 | YAML + metadata | **OPEN** — wait merge | PR from `phalanx-foundation` |
| A2 | TonAPI verification | `curl tonapi.io/v2/jettons/{minter}` | ton-assets merge | **graylist** | After merge → `whitelist` |
| A3 | Ston.fi pool | https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq | LP seeded | **Live** | Tx `9eb42e70…` |
| A4 | DexScreener pair | https://dexscreener.com/ton/eqam-5hxqpfql8_lqyvax4aeps9lxp6re8afr35hcfrpyztq | Pool live | **Indexed** | See [`DEXSCREENER-PROFILE.md`](DEXSCREENER-PROFILE.md) |
| A5 | DexScreener token profile | https://docs.dexscreener.com/token-listing | Logo + links | **TODO** | Boost optional (paid) |

---

## Tier B — Explorers & TON cards

| # | Platform | Submit URL | Gate | Status | Evidence |
|---|----------|------------|------|--------|----------|
| B1 | Tonscan labels | https://tonscan.org/labels | Verified addresses | **TODO** | [`TONSCAN-DYOR-SUBMIT.md`](TONSCAN-DYOR-SUBMIT.md) |
| B2 | DYOR.io | https://dyor.io/requests | Site + pool + description | **Indexed** | API probe `indexed: true` |
| B3 | Tonviewer contact | https://tonviewer.com/contact | Labels for treasury/LP | **TODO** | [`TRANSPARENCY.md`](TRANSPARENCY.md) |
| B4 | MyTonWallet assets | Follow ton-assets pattern | ton-assets merge helps | **TODO** | [`TONKEEPER-ASSET-SUBMISSION.md`](TONKEEPER-ASSET-SUBMISSION.md) |

---

## Tier C — Global aggregators

| # | Platform | Submit URL | Gate | Status | Evidence |
|---|----------|------------|------|--------|----------|
| C1 | CoinGecko | https://www.coingecko.com/en/coins/new | DEX + site + social | **TODO** | [`LISTING-SUBMISSION-PACK.md`](LISTING-SUBMISSION-PACK.md) |
| C2 | CoinMarketCap | https://coinmarketcap.com/request/ | Higher volume/LP | **TODO** | After CG + ~$10k/24h vol |
| C3 | GeckoTerminal | Auto from Ston.fi | Pool live | **Partial** | Same as DexScreener |

---

## Tier D — TON ecosystem programs

| # | Platform | Submit URL | Gate | Status | Evidence |
|---|----------|------------|------|--------|----------|
| D1 | TON Console | https://tonconsole.com | Product + TonAPI key | **Key in `.env`** | [`TON-CONSOLE-PLX.md`](TON-CONSOLE-PLX.md) — infra, not listing |
| D2 | tApps Center | https://ton.org/dev/opportunities/tapps-listing | Mini App demo | **TODO** | [`TAPPS-TON-FOUNDATION.md`](TAPPS-TON-FOUNDATION.md) |
| D3 | tonscan apps | https://t.me/SubmitAppBot | Public app URL | **TODO** | After Mini App |
| D4 | TON Foundation grants | https://ton.org / opportunities | Pitch + live product | **TODO** | Same doc |

---

## Tier E — CEX / Web3 (long shot)

| # | Platform | Notes | Status | Evidence |
|---|----------|-------|--------|----------|
| E1 | Binance Alpha | Pre-listing in Binance Wallet | **Research** | [`BINANCE-ALPHA-RESEARCH.md`](BINANCE-ALPHA-RESEARCH.md) |
| E2 | Binance Spot | Full CEX | **Not targeted** | — |

---

## Ops scripts (repo)

| Script | Purpose |
|--------|---------|
| **`scripts/plx-listing-automation.py`** | **Agent cron — checks + Telegram + PR nudge** ([`LISTING-AUTOMATION.md`](LISTING-AUTOMATION.md)) |
| `scripts/plx-dex-dashboard.py` | Price + swap snapshot |
| `scripts/plx-branding-swap.py` | Disclosed micro-MM (post-whitelist) |
| `scripts/lib/stonfi_swap.py` | Ston.fi simulate + queue |
| `scripts/stonfi-swap/` | Node executor (`npm install` on Acton server) |

---

## Recommended order

1. A1 merge → A2 whitelist  
2. A4/A5 DexScreener surface + deploy `plx.foundation` price chip  
3. B1–B3 Tonscan + DYOR + Tonviewer  
4. Organic quest [`TELEGRAM-QUEST-SWAPS.md`](TELEGRAM-QUEST-SWAPS.md)  
5. C1 CoinGecko when LP ≥ ~$5k recommended  
6. C2 CMC when volume supports  
7. D2–D4 when Mini App ready  
8. E1 research only — no wash volume for apply

---

*Last updated: 2026-06-09. Sync with [`POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md`](POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md).*
