# Insiden post-mainnet: label SCAM & kebingungan wallet

**Tanggal catatan:** 2026-06-03  
**Status:** Pemulihan metadata/registry — **on-chain tokenomics tidak rusak**

## Apa yang terasa “hancur” vs apa yang benar-benar rusak

| Gejala (pengalaman operator) | Akar masalah | Dampak bisnis | Bisa diperbaiki? |
|------------------------------|--------------|---------------|------------------|
| Label **SCAM** di Tonkeeper | TonAPI `verification: blacklist`; PR ton-assets [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) belum merge | Investor/retail tak percaya | **Ya** — merge + cache Tonkeeper |
| “Wallet salah” di Tonkeeper | Import **deployer** (0 PLX) atau mnemonic **testnet**, bukan `plx-*-mainnet` | Tampak seolah distribusi hilang | **Ya** — import wallet yang benar (lihat matriks di bawah) |
| Deploy pakai model mahal tanpa gate | Proses **Go/No-Go** tidak dijalankan sebelum announce | Kepercayaan & waktu hilang | **Ya** — gate + audit script (file ini + `MAINNET-GO-NO-GO.md`) |
| Web / toolkit belum jadi | Scope terpisah dari deploy kontrak | Tidak ada layanan retail | **Ya** — urutan kerja setelah SCAM/wallet |

**Bukan rusak (terverifikasi TonAPI, 2026-06-03):**

- Supply **1B PLX** di minter `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`
- Alokasi genesis: LP 400M, Treasury 250M, Community 200M, Vesting contract 100M, Marketing 50M
- Admin deployer `is_scam: false`
- Alamat di `MAINNET-DEPLOYMENT-RECORD.md` cocok dengan holder on-chain

## Koreksi: data wallet ADA di server (2026-06-03)

`wallets.toml` di `dev@100.100.168.168:~/projects/plx-acton` **berisi 6 mnemonic** (nama: `plx-deployer-v2`, `plx-treasury`, `plx-lp`, …).  
Wallet W5 menghasilkan alamat **berbeda** di testnet (`kQ…`) vs mainnet (`EQ…`) dari **24 kata yang sama**.

Verifikasi:

```bash
acton script scripts/print-addrs.tolk --net mainnet
```

→ treasury `EQBBlAF…` (250M PLX on-chain), LP `EQAiQ41…` (400M), dll.

**User “tidak punya data”** biasanya karena belum **export** mnemonic ke Tonkeeper — bukan karena hilang. Panduan: [`TONKEEPER-CARA-CONNECT.md`](TONKEEPER-CARA-CONNECT.md).

## Kegagalan proses (tanpa ganti rugi — tanggung jawab operasi)

1. **Announce / demo investor** sebelum `verification: whitelist` dan smoke Tonkeeper tanpa SCAM.
2. **PR ton-assets** dari fork pribadi, bukan org — jejak kurang formal untuk reviewer.
3. **Handoff wallet** tidak eksplisit: deployer ≠ treasury/LP; satu mnemonic tidak mengontrol semua PLX.
4. **Skrip deploy** default `PLX_DEPLOYER=plx-deployer-v2` (testnet name) vs docs `plx-deployer-v2-mainnet` — membingungkan ops, bukan mengubah alamat yang sudah ter-deploy.
5. **Gate “pastikan dulu”** ada di checklist tetapi tidak dieksekusi sebagai blocker otomatis.

## Matriks wallet (sumber kebingungan #1)

| Wallet Acton | PLX yang diharapkan | Untuk apa | Import ke Tonkeeper jika ingin… |
|--------------|--------------------:|-----------|----------------------------------|
| `plx-deployer-v2-mainnet` | **0** | Admin minter, drop-admin, deploy | Signing admin — **bukan** melihat treasury |
| `plx-lp-mainnet` | 400M | Likuiditas DEX | Spend / monitor LP |
| `plx-treasury-mainnet` | 250M | Ops, buyback | Spend / monitor treasury |
| `plx-community-mainnet` | 200M | Rewards | Spend / monitor community |
| `plx-marketing-mainnet` | 50M | Kampanye | Spend / monitor marketing |
| `plx-vesting-beneficiary-mainnet` | 0 sampai claim | Beneficiary tim | Claim vesting — PLX awal ada di **kontrak** vesting |

**Mnemonic testnet tidak akan membuka wallet mainnet di atas** — seed berbeda.

## Tindakan pemulihan (urutan)

1. Jalankan audit: `powershell -File .scripts/ops/audit-mainnet-plx.ps1` atau `bash .scripts/ops/audit-mainnet-plx.sh` (set `TONAPI_KEY` jika rate limit).
2. Eskalasi PR #5468 + email support@tonkeeper.com — minta penjelasan `blacklist` dan merge `jettons/PLX.yaml`.
3. Operator export mnemonic per wallet dari server (`list-mainnet-wallets.sh` + `acton wallet export-mnemonic`) — simpan offline.
4. **No-Go** investor pitch sampai `MAINNET-GO-NO-GO.md` checklist PASS.
5. Drop admin minter setelah yakin tidak perlu mint lagi (`drop-admin.tolk`).
6. Web/toolkit & LP — setelah 1–4 stabil.

## Bukti cepat untuk diri sendiri

```text
TonAPI GET /v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
→ verification: blacklist  (ini yang harus jadi whitelist)
→ holders: 5 dengan total 1B PLX
```

Lihat juga: [`TONKEEPER-SCAM-LABEL-APPEAL.md`](TONKEEPER-SCAM-LABEL-APPEAL.md), [`TONKEEPER-WALLET-IMPORT.md`](TONKEEPER-WALLET-IMPORT.md).
