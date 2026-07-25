# Tonkeeper USD verification — 2026-06-27

Probe: `python scripts/plx-tonkeeper-price-check.py` → `data/tonkeeper-price-probe.json`

## Result: NOT READY

| Check | Expected | Actual |
|-------|----------|--------|
| TonAPI verification | whitelist | whitelist |
| TonAPI rates USD | > 0 | **0** |
| Holders | ≥ 100 | **9** |
| Pool TON (Ston.fi) | ≥ 100 | **9.75** |
| DexScreener pair | indexed | **de-indexed** (pairs null) |
| Tonkeeper USD display | yes | **no** (expected until gates pass) |

## Operator blockers

1. **Deepen LP:** need ~90 TON more in pool; `plx-lp` has ~0.94 TON, `plx-treasury` ~0.02 TON — **external TON top-up required** before Ston.fi add liquidity.
2. **Holders:** need 91 more on-chain holders — populate `data/airdrop-season-queue.json` from `data/holder-growth-queue.template.json` and run `airdrop-season-batch.py`, plus toolkit onboarding.

## Next steps

See [`TONKEEPER-USD-PRICE-RUNBOOK.md`](TONKEEPER-USD-PRICE-RUNBOOK.md).

Re-run verification after Fase 1–2:

```powershell
python scripts/plx-tonkeeper-price-check.py
# exit 0 = tonkeeper_usd_ready true
```

Then Tonkeeper: refresh jetton balance; wait 15–60 min cache.
