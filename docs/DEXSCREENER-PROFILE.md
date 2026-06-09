# DexScreener — PLX profile & boost

Pair is already indexed (pool live). Next steps for **token profile** and optional promotion.

## Live links

- Pair: https://dexscreener.com/ton/eqam-5hxqpfql8_lqyvax4aeps9lxp6rE8AFr35hcfRPyZTq
- API: `GET https://api.dexscreener.com/latest/dex/pairs/ton/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq`

## Token profile submission

1. Read https://docs.dexscreener.com/token-listing
2. Prepare:
   - Logo: https://plx.foundation/plx-logo.png
   - Description: utility jetton, Phalanx Toolkit, audited contracts
   - Links: website, GitHub, Ston.fi pool, Telegram (when public)
3. Submit profile for minter `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`

## Optional paid boost

- API: `GET https://api.dexscreener.com/token-boosts/latest/v1`
- Check orders: `GET https://api.dexscreener.com/orders/v1/ton/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`
- Budget from **marketing wallet** — disclose in [`TRANSPARENCY.md`](TRANSPARENCY.md) if used

## Site integration

`plx.foundation/plx-token` links to DexScreener pair (see web component `DexLinksStrip`).

## Monitor

```bash
python scripts/plx-dex-dashboard.py --write
```
