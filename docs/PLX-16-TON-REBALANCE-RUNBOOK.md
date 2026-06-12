# PLX 16 TON Rebalance — runbook eksekusi (Jun 2026)

> SCAM/blacklist sudah hilang (`verification: graylist`). TON diskresioner ~16,1 TON di wallet **LP** (`plx-lp-mainnet`).

## A. Deepen LP (~10,35 TON) — operator dashboard

1. Login https://plx.foundation/dashboard → pilih deployment **mainnet PLX**.
2. Scroll **Grow your token** → **Add LP on Ston.fi** → mode **Top up existing LP**.
3. Masukkan **~10,35 TON** + PLX sesuai rasio pool (Simulate dulu).
4. Periksa kolom Simulate: TVL deepening, pool share, est. token price, total TON debited.
5. **Add liquidity** → tanda tangan TonConnect (2 kaki: TON + PLX).
6. Verifikasi **Historygram** checkpoint baru (step `liquidity`, badge cyan).
7. Opsional nanti: top-up ke 25 TON jika demand organik muncul.

**Jangan** wash-trade dari wallet sendiri untuk volume.

## B. Gas Pioneer Season (~3 TON LP → community)

Di server Acton (`dev@100.100.168.168:~/projects/plx-acton`):

```bash
bash scripts/transfer-lp-gas-to-community.sh
# dry-run: DRY_RUN=1 bash scripts/transfer-lp-gas-to-community.sh
```

Reward PLX: **2–5M** total Season 1 (bukan 200M). Batch: `scripts/airdrop-season-batch.sh`.

## C. Float quest-swap (~2 TON)

Sisakan di wallet LP/treasury setelah A+B. Untuk insentif swap **peserta asli** — bukan muter volume sendiri.

## D. Buffer ops (~6 TON)

Cadangan gas, listing opsional berbayar, darurat. **Jangan** seed DeDust.

## E. Whitelist Tonkeeper (0 TON)

PR live: https://github.com/tonkeeper/ton-assets/pull/5540

```bash
bash scripts/verify-tonkeeper-whitelist.sh
```

## F. DexScreener re-index

Otomatis setelah TVL naik + swap asli. Cek:

```bash
curl -s "https://api.dexscreener.com/token-pairs/v1/ton/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
```

## G. Premium hold gate

**25.000 PLX** — deployed via plx-toolkit (`PLX_HOLD_MINIMUM`).

## Alokasi ringkas (dari 16,1 TON)

| Bucket | TON | Status |
|--------|-----|--------|
| A LP deepen | ~10,35 | User via dashboard |
| B Pioneer gas | 3,0 | `transfer-lp-gas-to-community.sh` |
| C Quest float | 2,0 | Reserve |
| D Ops buffer | ~0,75+ | Setelah A+B (sisanya) |

*Catatan: setelah A, sisa LP wallet ~5,75 TON; setelah B transfer 3 TON, sisa ~2,75 TON untuk C+D.*
