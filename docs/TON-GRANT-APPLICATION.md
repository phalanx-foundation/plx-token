# TON Foundation Grant Application — Phalanx (PLX)

> **Status:** DRAFT (model 2026) — siap submit via portal ecosystem TON.
> **Dibuat ulang:** 2026-09-06. Versi lama (2026-07-10) **tidak valid** karena masih merujuk `builders.ton.org` (portal deprecated) dan model grant lama.
> **Posisi:** **Contender** (early-stage; naik ke **Champion** setelah traction) — vertikal **Simplified DeFi** (primary) + **Telegram In-App Economy** (secondary) + **open-source public goods**.

---

## 0. Update penting (2026)

- **`builders.ton.org` sudah deprecated.** Jangan dipakai. Portal & aplikasi grant TON sekarang via **TON Foundation / ecosystem portal** (lihat [ton.org/en/ton-grants](https://ton.org/en/ton-grants)).
- Model grant sekarang **milestone-based**: dana cair hanya setelah progress terukur. Dua tier: **Contenders** (early-stage) dan **Champions** (established, high scaling).
- 5 vertikal prioritas: **AI**, **Simplified DeFi**, **Telegram In-App Economy**, **Payments**, **GameFi**.
- **TON Society Grants & Bounties (GitHub) sedang PAUSED** — jangan andalkan; pantau.

---

## 1. Project Identity

| Item | Detail |
|------|--------|
| Nama | Phalanx (PLX) |
| One-liner | No-code audited Jetton deployer & launchpad on TON |
| Web | https://plx.foundation |
| Mini App | https://app.plx.foundation |
| GitHub (public) | https://github.com/phalanx-foundation/plx-token |
| Bot | @phalanxfoundationbot |
| Minter (mainnet) | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| Pool STON.fi | `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq` |

## 2. Vertikal (sesuai prioritas TON)

- **Primary:** Simplified DeFi — siapa pun bisa deploy Jetton berfitur lengkap (vesting, staking, governance, anti-whale) **tanpa kode**, dalam 5 menit.
- **Secondary:** Telegram In-App Economy — Mini App + bot untuk deploy, earn, dan growth.
- **Public goods:** 22 kontrak MIT yang bisa dipakai ulang project TON lain.

## 3. Mengapa PLX cocok

1. **Menurunkan barrier to entry.** TON punya 180M+ kontrak, tapi deploy Jetton profesional butuh 2–3 bulan + audit ($15K–$50K). Phalanx: 5 menit di browser.
2. **Open-source public good.** 22 kontrak MIT — `TokenStaking`, `TokenGovernance`, `LiquidityLocker`, `PaymentSplitter`, `TeamVesting`, standar `JettonMinter`/`JettonWallet` TEP-74/64.
3. **TON-native.** Toolchain resmi (Acton + Tolk), TON Connect, TEP standards, audit-first (60/60 Acton tests).
4. **Ecosystem multiplier.** Setiap project yang deploy via Phalanx = komunitas + volume DEX + holder baru untuk TON.

## 4. Traction (jujur, per 2026-09-06)

| Metrik | Nilai |
|--------|-------|
| On-chain holders | 9 (5 distribution wallets + vesting + LP + toolkit) |
| Ston.fi LP | ~9.75 TON + ~95,929 PLX (~$34) |
| Smart contracts | 22 (compiled + tested) |
| Automated tests | 72 passing (7 test files) |
| Toolkit pricing | 3 tiers (Free, Standard 20 TON, Pro) |
| Bot commands | 5 aktif |

> ⚠️ **Jujur soal traction:** ini **masih kecil**. Karena itu kami mengajukan sebagai **Contender** dan menargetkan grant yang jelas-jelas **milestone-based** (bukan "kami sudah besar"). Ini juga alasan aplikasi **STON.fi** dan **Microsoft/Google cloud credits** (yang tidak butuh traction besar) dijalankan **paralel** — lihat `GRANTS-INVESTOR-INDEX.md`.

## 5. Ask (dana)

| Penggunaan | Amount | Tujuan |
|------------|--------|--------|
| LP bootstrap (STON.fi PLX/TON) | 50–80 TON | Naikkan pool ke $3K–$5K (dengan matching PLX dari treasury) |
| Third-party audit | 20 TON | Audit `TokenStaking` + `TokenGovernance` |
| **Total** | **70–100 TON** | ~$115–$164 (harga GRAM saat ini) |

## 6. Milestones (milestone-based, verifiable on-chain)

| Milestone | Deliverable | Verifikasi |
|-----------|-------------|------------|
| **M1: LP deepening** | Deploy grant TON + matching PLX ke pool STON.fi | On-chain TX + DexScreener |
| **M2: Tonkeeper USD** | Gate 100 TON LP + 100 holders | Tonkeeper tampilkan harga PLX |
| **M3: Mainnet contracts** | Deploy `TokenStaking` + `TokenGovernance` + `LockVault` | Alamat kontrak on-chain |
| **M4: Audit** | Third-party audit selesai | Laporan audit publik |
| **M5: Toolkit launch** | E2E semua 6 template | Deploy live via `/build` |
| **M6: Listing** | Gate volume/LP/holder CMC & CoinGecko | Halaman CG/CMC live |

## 7. Jalur paralel yang lebih cocok untuk stage sekarang

Selain Champion/Contender, ada **Telegram Web3 Grants** dengan tipe yang lebih sesuai:

- **Type A – Initial Deployment** (hingga $10K TON): untuk aplikasi Web Apps / infra TON. PLX sudah live → cocok.
- **Type B – Live TON project** (hingga $10K TON): project TON live yang belum integrasi penuh.

## 8. Tidak ada di repo

- Mnemonic, `wallets.toml`, `.env`, folder investor/MONETIZATION **tidak** boleh di-commit. Draft ini aman di `docs/` (tidak menyertakan secret).
- Bila butuh **data room / pitch deck**, buat terpisah dan jangan di-commit ke repo publik.

---

## Cara submit (manusia)

1. Buka https://ton.org/en/ton-grants → cek program aktif & kriteria terbaru (ubah angka jika berubah).
2. Hubungkan wallet TON (Tonkeeper) jika portal meminta.
3. Isi form aplikasi (copy section 1–8 di atas).
4. Lampirkan: lintasan GitHub, Tonkeeper PR, demo `/build` (video/GIF 2–3 menit), hasil test.
5. Follow-up setelah 2–4 minggu; pantau status di `GRANTS-INVESTOR-INDEX.md`.

---

*Dibuat ulang: 2026-09-06. Perbarui setelah submit & respons.*
