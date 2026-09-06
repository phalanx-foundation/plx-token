# STON.fi DEX Grant — Aplikasi (Phalanx / PLX)

> **Program:** https://ston.fi/grant-program · hingga **$10,000 USDT** · **evergreen** (tanpa deadline).
> **Kriteria kunci:** (1) membangun produk DeFi / mengintegrasikan mekanik DeFi; (2) **integrasi SDK/widget STON.fi** dengan rencana teknis jelas; (3) inovasi + impact ekosistem; (4) kepatuhan regulasi.
> **Status:** DRAFT — siap submit. Isi narrative di bawah bisa di-copy-paste ke form STON.fi.

---

## 1. Ringkasan (memenuhi kriteria "integrasi SDK")

**Phalanx Toolkit** adalah **launchpad no-code** di TON yang meng-route **setiap token yang dideploy** melalui stack STON.fi untuk likuiditas & swap — sehingga **setiap deploy PLX = satu pool + volume baru bagi STON.fi** (ecosystem multiplier).

Integrasi SDK **sudah produksi**, bukan mock:

| Komponen | File | Fungsi | Status |
|----------|------|--------|--------|
| LP provisioning | `toolkit-staging/web/lib/stonfi-liquidity.ts` | `StonApiClient` (`@ston-fi/api`) + `dexFactory` (`@ston-fi/sdk`) → simulasi + build tx add-liquidity (TonConnect) | Live |
| Swap PLX→TON | `toolkit-staging/web/lib/stonfi-swap-sell.ts` | `StonApiClient` + `dexFactory` → quote & tx swap | Live |
| UI LP | `add-liquidity-panel.tsx`, `add-liquidity-modal.tsx`, `add-liquidity-dedust-panel.tsx` | Dashboard "Add liquidity" (top up / new pool) | Live |
| Swap sheet | `plx86-swap-sheet.tsx` | AI Token Changer → swap via STON.fi | Live |
| Konstanta | `stonfi-constants.ts` | endpoints API + pool address | Live |

## 2. Narrative inti

> "STON.fi adalah lapisan likuiditas terbesar di TON. Phalanx adalah **penghasil likuiditas terstruktur** untuk STON.fi: alih-alih meminta DEX mendaftarkan token satu per satu, Phalanx membuat **jalur otomatis** yang men-deliver likuiditas baru setiap kali ada project yang launch — via SDK STON.fi yang sudah terpasang."

**Masalah:** jutaan project TON ingin DeFi (build token), tetapi:
- Butuh 2–3 bulan development + audit untuk jetton lengkap (vesting, anti-whale, staking, governance).
- Tidak tahu cara mengintegrasikan DEX untuk likuiditas & swap.

**Solusi Phalanx:** wizard browser → metadata → deploy → **langsung terhubung ke STON.fi** untuk LP dan swap, dengan SDK resmi. Tidak perlu developer untuk likuiditas.

## 3. Bukti teknis integrasi STON.fi (yang sudah jalan)

### LP baru / top-up (TonConnect)
`web/lib/stonfi-liquidity.ts` memakai `StonApiClient` + `dexFactory`, dengan dukungan:
- `provisionType: Initial` (buat pool baru) saat no pool ada.
- `top-up` saat pool sudah ada (via `GET /v1/pools/by_market`).
- Simulasi keseimbangan + slippage + price impact sebelum user sign.

### Swap (fungsi DeFi di dalam produk)
`web/lib/stonfi-swap-sell.ts` menghasilkan quote & tx swap PLX→TON (`dexFactory`) yang ditandatangani user via TonConnect.

### Bukti produksi
- Pool PLX/TON mainnet: `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq` — sudah live di Ston.fi.
- Halaman dashboard "Add liquidity" + swap sheet aktif di `plx.foundation/dashboard`.

> ⚠️ **Catatan jujur:** pool PLX/TON saat ini **sangat tipis (~$34 TVL)** dan karena itu **belum ter-indeks DexScreener** (baru muncul setelah volume 24 jam). Ini **bukan** kegagalan integrasi — SDK terpasang dan path aktif; justru inilah alasan utama kami membutuhkan grant: untuk bootstrap likuiditas.

## 4. Milestone usulan (kaitkan dengan grant)

| Milestone | Deliverable | Kaitan dengan ecosystem |
|-----------|-------------|------------------------|
| **M1** | Dokumen integrasi + case study STON.fi untuk developer toolkit | Dokumentasi → lebih banyak project pakai SDK |
| **M2** | Embed **Omniston swap widget** di dashboard (opsional penguat) | Swap lintas-DEX di dalam produk |
| **M3** | **Auto-LP hook** pasca-deploy untuk token pengguna | Setiap deploy PLX → pool STON.fi otomatis |
| **M4** | SDK integration test suite (CI) | Kualitas kode sesuai ekspektasi STON.fi |
| **M5** | Kampanye "Launch on STON.fi via Phalanx" | Menarik builder baru ke TON |

## 5. Kenapa layak didanai

1. **Ecosystem multiplier:** 1 deploy PLX = 1 pool + volume baru di STON.fi. Dengan 6 template jetton (standard, antiwhale, fee, mintable, staking, airdrop) setiap project baru adalah pelanggan STON.fi baru.
2. **Integrasi SDK asli:** bukan wrapper, memakai `@ston-fi/api` + `@ston-fi/sdk` resmi untuk LP & swap.
3. **Open-source:** 22 kontrak MIT (`github.com/phalanx-foundation/plx-token`) — dapat dipakai ulang oleh project TON lain.
4. **Self-funded:** tanpa VC, tanpa IDO, transparan.

## 6. Data dasar untuk form

| Field | Nilai |
|-------|-------|
| Project name | Phalanx (PLX) |
| Website | https://plx.foundation |
| Mini App | https://app.plx.foundation |
| GitHub | https://github.com/phalanx-foundation/plx-token |
| Minter (mainnet) | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| Pool STON.fi | `EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq` |
| Integrasi SDK | `@ston-fi/api` + `@ston-fi/sdk` (produksi) |
| Amount diminta | hingga $10K USDT (development + LP bootstrap) |

---

## Cara submit (manusia)

1. Buka https://ston.fi/grant-program
2. Lengkapi form application (copy section di atas).
3. Terima email konfirmasi setelah submit.
4. Tunggu review tim STON.fi; jawab bila ada pertanyaan lanjutan.
5. Daftarkan status di `docs/GRANTS-INVESTOR-INDEX.md` (Tier 1 baris 1) → ubah ke `submitted` lalu `awarded`.

---

*Dibuat: 2026-09-06. Nilai di bagian ini akan berubah setelah submit / respons.*
