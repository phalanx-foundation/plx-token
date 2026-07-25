# Tonkeeper USD price — runbook operator

Tonviewer **verified** dan baris **USD** di Tonkeeper adalah lapisan berbeda. PR ton-assets #5540 sudah merged; TonAPI `verification: whitelist`. Jika saldo PLX tampil tanpa nilai dollar, ikuti runbook ini.

**Minter:** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`  
**Pool:** `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq`

---

## Diagnosis cepat

```powershell
curl.exe -sS "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
# verification: whitelist, holders_count: N

curl.exe -sS "https://tonapi.io/v2/rates?tokens=EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS&currencies=usd"
# USD > 0 → Tonkeeper bisa menampilkan fiat; USD = 0 → tidak
```

Indexer TonAPI (opentonapi) memakai ambang kira-kira:

| Gate | Target | Probe 2026-06-23 |
|------|--------|------------------|
| Pool reserve (TON side) | ≥ **100 TON** | ~9.75 TON |
| Holders | ≥ **100** | 9 |
| TonAPI rates USD | > 0 | 0 |

DexScreener dapat menampilkan harga dengan LP ~$30 — **tidak** memenuhi gate TonAPI untuk wallet.

---

## Fase 1 — Deepen LP (`plx-lp`)

Wallet: **plx-lp** (400M PLX genesis). Modal TON dari treasury atau transfer internal.

**Probe on-chain (otomatis):** `python scripts/plx-tonkeeper-price-check.py` — lihat `data/tonkeeper-price-probe.json` untuk pool TON, holders, rates.

| Wallet | Alamat EQ | TON balance (probe) |
|--------|-----------|---------------------|
| plx-lp | `EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH` | ~0.94 TON — **tidak cukup** untuk deepen |
| plx-treasury | `EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX` | ~0.02 TON — **top-up eksternal** diperlukan sebelum transfer ke LP |

Sebelum add liquidity: transfer **~95 TON** dari treasury → plx-lp (internal), lalu langkah Ston.fi di bawah.

1. Import **plx-lp** di Tonkeeper mainnet ([`TONKEEPER-CARA-CONNECT.md`](TONKEEPER-CARA-CONNECT.md)).
2. Pastikan saldo TON ≥ **~95 TON** untuk add liquidity (+ gas).
3. Buka [Ston.fi pool](https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq) → **Add liquidity**.
4. Tambah ~**90 TON** + PLX sesuai rasio UI (jangan jauh dari mid-price).
5. Konfirmasi tx di Tonkeeper; catat hash di [`TRANSPARENCY.md`](TRANSPARENCY.md) jika material.

**Risiko:** impermanent loss; LP tipis mudah dimanipulasi — lihat [`AKUNTABILITAS-SCAM-DAN-LP.md`](AKUNTABILITAS-SCAM-DAN-LP.md).

**Otomatisasi disclosed:** `python scripts/plx-branding-swap.py` (micro-swap organik, post-whitelist).

---

## Fase 2 — Grow holders (≥ 100)

Setiap wallet dengan saldo PLX > 0 di jetton wallet = +1 holder on-chain.

| Jalur | Wallet | Script / aksi |
|-------|--------|----------------|
| Toolkit onboarding | User TonConnect | Dorong sign-up + rail PLX di toolkit |
| Pioneer / season airdrop | `plx-community` (200M) | `python scripts/airdrop-season-batch.py` + `data/airdrop-season-queue.json` |
| Swap quest | Publik | [`TELEGRAM-QUEST-SWAPS.md`](TELEGRAM-QUEST-SWAPS.md) |
| Retention campaign | Marketing | [`PLX-AIRDROP-AND-RETENTION-CAMPAIGN.md`](PLX-AIRDROP-AND-RETENTION-CAMPAIGN.md) |

Pantau: `holders_count` di TonAPI jetton endpoint atau `plx-listing-automation.py`.

---

## Fase 3 — Verifikasi Tonkeeper

Setelah Fase 1–2:

```powershell
curl.exe -sS "https://tonapi.io/v2/rates?tokens=EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS&currencies=usd"
# Harus: "USD": <positive number>

curl.exe -sS "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | findstr holders_count
# Harus: >= 100
```

Di Tonkeeper: pull-to-refresh atau re-import jetton; cache ~15–60 menit.

Cron monitoring: `scripts/plx-listing-automation.py` (alert Telegram jika whitelist tapi rates = 0).

---

## Token terkunci (bukan bug Tonkeeper)

PLX di **kontrak vesting** atau **PlxLockVault** (belum deployed mainnet) tidak muncul sebagai saldo jetton wallet. Tonkeeper tidak menampilkan USD untuk posisi terkunci — hanya toolkit/app Phalanx jika UI ada.

---

## Tidak perlu

- Re-submit ton-assets (#5540 merged)
- Redeploy minter untuk harga
- Ticket Tonkeeper "force price" (tidak ada API publik)
