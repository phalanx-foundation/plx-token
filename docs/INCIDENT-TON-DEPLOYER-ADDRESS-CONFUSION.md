# Insiden: kebingungan alamat deployer & TON (mainnet)

**Ringkas:** Agent sempat memberi **alamat deployer yang salah** (`EQBg9RF…`), lalu membatalkan dan menyuruh **jangan transfer**. Wallet yang benar untuk deploy mainnet adalah **`EQBfYLpq…` / `UQBfYLpq…`** (sama raw `0:5f60ba6a…`).

## Kronologi kesalahan agent (bukan kesalahan user)

| Urutan | Apa yang agent katakan | Fakta |
|--------|------------------------|-------|
| 1 | `kQ` testnet = `EQ` mainnet, **raw address sama** | **Salah** untuk wallet W5 (v5r1) — mainnet ≠ testnet raw |
| 2 | Kirim 5 TON ke `EQBg9RFEVaQIh3xVonBxCnIb2Vw19y-rSD4uO1LR0eNH4498` | Itu alamat **testnet** deployer-v2 (`0:60f511…`), **bukan** mainnet |
| 3 | “Jangan transfer, Anda sudah benar di `UQBfYLpq…`” | **Benar** — TON user memang di deployer mainnet yang dipakai deploy |

User yang mengikuti langkah 2 **sebelum** langkah 3 bisa panik; on-chain, alamat `EQBg9RF…` di mainnet **tidak pernah aktif** (0 TON, nonexist) — artinya transfer ke sana **tidak terjadi** atau tidak pernah masuk mainnet.

## Verifikasi on-chain (2026-06-03)

| Alamat | Raw | TON mainnet | Arti |
|--------|-----|-------------|------|
| **Benar** `EQBfYLpq…` / `UQBfYLpq…` | `0:5f60ba6a…b0dd1a9e` | ~0 (habis untuk gas deploy) | Deployer mainnet — **ini yang dipakai** `deploy-distribution.tolk` |
| **Salah (saran agent)** `EQBg9RF…` | `0:60f511…1e347e3` | 0, nonexist | Testnet deployer — **jangan kirim TON mainnet ke sini** |

Deploy mainnet **berhasil** (log server): minter, 1B PLX, vesting, splitter — deployer di log = `EQBfYLpq…`.

**Kesimpulan:** TON Anda **tidak “dipindah ke wallet batu”** oleh blockchain; yang terjadi adalah **narasi agent bolak-balik**. TON di wallet benar **dipakai biaya deploy** (~5 TON gas), bukan hilang ke alamat palsu.

## Yang user lakukan dengan benar

- Menyimpan / fund wallet **V5** di Tonkeeper (`UQBfYLpq…`).
- **Tidak wajib** transfer ke `EQBg9RF…` jika sempat dibaca pesan “jangan transfer”.

## Satu sumber kebenaran ke depan

```bash
ssh dev@100.100.168.168
cd ~/projects/plx-acton
~/.acton/bin/acton script scripts/print-addrs.tolk --net mainnet
```

Baris `plx-deployer-v2 -> EQBfYLpq…` = deployer resmi.

## Connect mnemonic

Lihat [`TONKEEPER-CARA-CONNECT.md`](TONKEEPER-CARA-CONNECT.md) — 24 kata di `wallets.toml` server, nama Acton `plx-deployer-v2` (bukan file terpisah “mainnet”).
