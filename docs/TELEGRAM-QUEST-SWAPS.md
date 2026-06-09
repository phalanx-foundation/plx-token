# Telegram quest — first organic PLX swaps

Goal: spread **real** DexScreener transactions across wallets (not one round-trip).

## Prerequisites

- Pool: https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
- Participants have Tonkeeper + ~0.15 TON (swap + fees)

## Quest rules

1. Swap **≥ 0.05 TON → PLX** on Ston.fi (mainnet pool above).
2. Post **Tonviewer transaction link** in Telegram thread (not screenshot only).
3. Optional: hold PLX — no requirement to sell.

## Post template (copy to Telegram)

```
PLX mainnet swap quest (builders)

1. Open Ston.fi pool:
https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq

2. Swap ≥ 0.05 TON → PLX (import jetton minter if needed):
EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS

3. Reply with Tonviewer tx link.

Utility token — Phalanx Toolkit. Not investment advice.
Site: https://plx.foundation/plx-token
```

## Ops disclosure

If team runs **disclosed** micro-swaps from ops wallets, say so in same channel ([`TRANSPARENCY.md`](TRANSPARENCY.md) — liquidity awareness program).

## Success metrics (7 days)

| Metric | Target |
|--------|--------|
| Unique Tonviewer tx links | ≥ 10 |
| DexScreener 24h txns | > 1 buy / 1 sell |
| Holder count (TonAPI) | Up from baseline |

Track: `python scripts/plx-dex-dashboard.py`
