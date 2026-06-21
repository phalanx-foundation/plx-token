# PLX market dashboard

Live price, volume, DexScreener chart, and recent pool swaps for **PLX/TON** on Ston.fi.

## Quick start

```bash
# Print summary to terminal
python3 scripts/plx-dex-dashboard.py

# Generate snapshot + HTML (cron-friendly)
python3 scripts/plx-dex-dashboard.py --write

# Open in browser (after --write)
python3 scripts/plx-dex-dashboard.py --serve
# → http://127.0.0.1:8765/docs/plx-market-dashboard.html
```

Windows:

```powershell
python scripts\plx-dex-dashboard.py --write
python scripts\plx-dex-dashboard.py --serve
```

## Outputs

| File | Purpose |
|------|---------|
| `data/market-snapshot.json` | Machine-readable snapshot for scripts |
| `docs/plx-market-dashboard.html` | Standalone dashboard (embed chart + stats) |

## Environment (optional)

Uses defaults for mainnet PLX pool if unset:

```env
STONFI_POOL_ADDRESS=EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
PLX_JETTON_MINTER_MAINNET=EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
```

## Cron (Ubuntu Acton server)

```bash
*/15 * * * * cd ~/projects/plx-acton && python3 scripts/plx-dex-dashboard.py --write >> logs/market-dashboard.log 2>&1
```

## Reading DexScreener transactions

On DexScreener (and this dashboard):

- **Buy** — someone spent **TON** to receive **PLX** (purchase on the DEX).
- **Sell** — someone sold **PLX** for **TON**.

Each row is one **swap** through the Ston.fi pool, not a toolkit payment or off-chain transfer.

## External links

- [DexScreener pair](https://dexscreener.com/ton/eqam-5hxqpfql8_lqyvax4aeps9lxp6rE8AFr35hcfRPyZTq)
- [Ston.fi pool](https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq)
