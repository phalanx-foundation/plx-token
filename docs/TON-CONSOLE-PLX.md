# Hubungkan proyek PLX dengan TON Console

> **TON Console** = dashboard TonAPI (rate limit, webhook, analytics, invoicing).  
> **Bukan** pengganti verifikasi Tonkeeper — label SCAM tetap lewat PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468).

---

## Tonviewer “Suspected” + popup bergoyang — bukan menu Console

| Yang Anda lihat di Tonviewer | Artinya |
|------------------------------|---------|
| Halaman **Suspected** / peringatan goyang | UI Tonviewer karena TonAPI `verification: **blacklist**`** — sama data di popup “Where do we get information from?” |
| Popup “Use **tonapi.io**” | Hanya **menjelaskan sumber data** (read-only), bukan tempat connect project |
| Menu / tab **Jetton** di Tonviewer | Tampilan explorer untuk alamat minter — **bukan** TON Console |

**TON Console** = situs terpisah **https://tonconsole.com** (dashboard API key). Tidak ada tombol “connect jetton” di Tonviewer yang mengganti PR ton-assets.

---

## Apa yang dihubungkan

| Lapisan | Alamat / ID | Peran |
|---------|-------------|--------|
| Jetton minter (PLX) | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` | Token utama — query metadata, holders, verifikasi |
| Treasury | `EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX` | Ops / buyback |
| LP | `EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH` | Likuiditas |
| PaymentSplitter | `EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv` | Pembayaran toolkit |
| Team Vesting | `EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l` | 100M terkunci |

Detail: [`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md).

---

## Langkah 1 — Di TON Console (Anda, ~5 menit)

1. Buka https://tonconsole.com → **Connect** (Telegram).
2. **Create project** (atau buka project yang sudah ada):
   - **Name:** `Phalanx PLX` atau `Phalanx Foundation`
   - **Description (opsional):** paste baris minter + link repo:
     ```
     PLX mainnet minter: EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
     https://github.com/phalanx-foundation/plx-token
     https://plx.foundation/plx-token
     ```
3. Menu **TonAPI** → **API keys** → **Create key**.
4. Salin key (format panjang, sekali tampil) — jangan kirim ke chat/GitHub.

Docs resmi: https://docs.tonconsole.com/tonapi/dapp/building

---

## Langkah 2 — Simpan key di repo lokal (gitignored)

Edit `D:\DATA TOOLS\PLX-ACTON\.env`:

```env
TONAPI_KEY=<paste-key-dari-ton-console>
# atau nama yang sama:
# CONSOLE_TOKEN=<key yang sama>
```

`load-env.ps1` menyalin `CONSOLE_TOKEN` → `TONAPI_KEY` bila `TONAPI_KEY` kosong.

Opsional — agar skrip/toolkit tahu mainnet PLX tanpa hardcode:

```env
PLX_JETTON_MINTER_MAINNET=EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
PLX_TREASURY_MAINNET=EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX
PLX_LP_MAINNET=EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH
PLX_SPLITTER_MAINNET=EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv
```

Muat env:

```powershell
powershell -File "D:\DATA TOOLS\PLX-ACTON\.scripts\ops\load-env.ps1"
```

---

## Langkah 3 — Verifikasi koneksi (agent / Anda)

```powershell
powershell -File "D:\DATA TOOLS\PLX-ACTON\.scripts\ops\test-tonapi-key.ps1"
```

Harus keluar: `OK` + nama jetton **Phalanx** + `verification: blacklist` atau `whitelist`.

Jika `401` / `403` → key salah atau belum di-copy penuh.

---

## Langkah 4 — Toolkit & produksi (plx.foundation)

Satu key TonAPI dipakai di **dua** tempat (nilai **identik**):

| Tempat | Variable | Catatan |
|--------|----------|---------|
| Railway → service `plx-toolkit` | `TONAPI_KEY` | API backend (`api.plx.foundation`) |
| Cloudflare Pages → web prod | `TONAPI_KEY` atau `NEXT_PUBLIC_TONAPI_KEY` | Jika web panggil TonAPI dari browser |

**Jangan** commit key ke GitHub. Set manual di dashboard Railway/Cloudflare (sama seperti `DATABASE_URL`).

Setelah set di Railway, redeploy tidak wajib jika hanya tambah variable — restart service jika API sudah jalan.

---

## Langkah 5 — Opsional di Console (nanti)

| Fitur Console | Untuk PLX |
|---------------|-----------|
| **Webhooks** | Notifikasi transfer ke treasury / splitter |
| **TON Payment / Invoices** | Pembayaran toolkit — butuh daftar app + wallet penerima ([docs](https://docs.tonconsole.com/tonconsole/invoices)) |
| **Analytics SQL** | Volume, holders (setelah traffic) |

Wallet penerima invoice yang masuk akal: **PaymentSplitter** `EQBC3QoFri…` atau treasury — sesuai alur bisnis toolkit.

---

## “Sudah connect Console — kenapa token belum terbaca / masih Suspected?”

Dua arti **“terbaca”** sering dicampur:

| Arti | Sudah? | Siapa yang mengatur |
|------|--------|---------------------|
| **A. Data on-chain** (nama, supply, holders, tx) | **Ya** — TonAPI sudah baca Phalanx/PLX | Indexer TonAPI (otomatis setelah deploy) |
| **B. Status aman / whitelist** (bukan SCAM/FAKE/Suspected) | **Belum** — masih `verification: blacklist` | **Hanya** merge `tonkeeper/ton-assets` PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) |

**API key TON Console** hanya membantu **A** (kuota/lebih stabil saat app Anda panggil API). Key **tidak** mendaftarkan jetton ke daftar verifikasi Tonkeeper — itu **bukan** menu “Jetton” di Console yang mengganti PR.

```
Connect Console + CONSOLE_TOKEN di .env
        │
        ├─► TonAPI bisa baca jetton (metadata, holders)     ✅ sudah
        │
        └─► verification → whitelist di wallet/explorer   ❌ tetap blacklist
                              sampai PR ton-assets merge
```

**Di Tonkeeper:** add custom jetton (minter `EQCbaUJqi…`) → saldo **tampil**, label SCAM **bisa tetap** sampai **B** selesai.

**Di TON Console dashboard:** tidak ada “publish token ke index Tonkeeper” — project + API key untuk **aplikasi Anda** (toolkit), bukan katalog publik ton-assets.

---

## Yang Console **tidak** lakukan

| Harapan | Realita |
|---------|---------|
| Hapus label SCAM Tonkeeper | Hanya merge **ton-assets** |
| Buat harga PLX otomatis | Perlu LP di Ston.fi |
| Ganti wallet deploy | Tidak — hanya API baca/tulis tx via dApp Anda |

---

## Troubleshooting

| Gejala | Solusi |
|--------|--------|
| Rate limit tanpa key | Tambahkan `TONAPI_KEY` |
| Jetton tidak ditemukan | Pastikan query pakai minter **EQCbaUJqi…** mainnet |
| Key di `.env` tapi toolkit gagal | Copy key yang sama ke **Railway Variables** |
| Dua project Console | Pakai **satu** key prod untuk Phalanx; jangan campur testnet |

---

## Checklist

- [ ] Project dibuat di https://tonconsole.com
- [ ] API key dibuat & disimpan di `.env` lokal
- [ ] `test-tonapi-key.ps1` → OK
- [ ] `TONAPI_KEY` di Railway (+ CF jika perlu)
- [ ] PR ton-assets #5468 tetap dikejar (terpisah dari Console)

## Verifikasi prod (2026-06-09)

| Check | Result |
|-------|--------|
| `GET https://api.plx.foundation/health/db` | `connected` |
| `test-tonapi-key.ps1` (lokal `.env`) | Jalankan setelah paste key dari tonconsole.com |
| TonAPI `verification` | `graylist` sampai PR [#5540](https://github.com/tonkeeper/ton-assets/pull/5540) merge |

*Terakhir diperbarui: 2026-06-09*
