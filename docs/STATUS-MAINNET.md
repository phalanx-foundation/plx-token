# Status mainnet PLX (live snapshot)

**Terakhir diperbarui:** 2026-06-03  
**Untuk:** operator & investor — satu halaman kebenaran.

## Sudah live (tanpa uang user lagi)

| Item | Status |
|------|--------|
| Jetton minter | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| Supply | 1 000 000 000 PLX |
| Genesis distribusi | LP 400M, Treasury 250M, Community 200M, Vesting 100M, Marketing 50M |
| Wallet W5 user (Tonkeeper) | **Cocok** dengan deploy (6 wallet `UQ…` terverifikasi screenshot) |
| Metadata + logo | `https://plx.foundation/plx-logo.png` on-chain |
| Deploy ulang 5 TON | **Tidak perlu** |

## Blocker utama (gratis, tunggu pihak ketiga)

| Blocker | Status | Tindakan |
|---------|--------|----------|
| Label **SCAM** Tonkeeper | `verification: blacklist` | PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) + email `support@tonkeeper.com` |
| Announce investor | **No-Go** | Lihat [`MAINNET-GO-NO-GO.md`](MAINNET-GO-NO-GO.md) |

## Bukan blocker kontrak

| Item | Catatan |
|------|---------|
| Alamat wallet “salah” | **Dibatalkan** — user W5 cocok; lihat [`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md) |
| PLX tidak di chain | Tidak — cek [Tonviewer minter](https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS) |
| Ston.fi LP | Butuh modal TON+PLX terpisah — 400M PLX sudah di wallet LP on-chain |

## Tampilkan PLX di Tonkeeper (user)

1. Mainnet aktif.  
2. **Add custom token** → minter `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`.  
3. Buka wallet Treasury / LP — saldo PLX genesis.

## Gas ops (tanpa fiat user)

Deployer ~0 TON; treasury/LP ~0,05 TON each. Ops dapat mengirim ~0,03 TON treasury → deployer via `scripts/send-ton.tolk` di server (kunci di `wallets.toml`).

## Insiden agent (akuntabilitas)

- [`INCIDENT-TON-DEPLOYER-ADDRESS-CONFUSION.md`](INCIDENT-TON-DEPLOYER-ADDRESS-CONFUSION.md)  
- Narasi V4R2 / “restore mainnet wallet” **salah** untuk user ini — ditarik.
