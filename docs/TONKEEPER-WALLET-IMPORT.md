# Import wallet mainnet ke Tonkeeper

Panduan singkat untuk operator Phalanx. **Mnemonic testnet tidak menggantikan** mnemonic wallet operasional mainnet.

## Fakta penting

| Pertanyaan | Jawaban |
|------------|---------|
| Satu mnemonic untuk semua wallet mainnet? | **Tidak.** Setiap `acton wallet new` = 24 kata baru. |
| Mnemonic testnet bisa import treasury/LP mainnet? | **Tidak** — alamat mainnet berbeda dari testnet. |
| Mnemonic testnet di Tonkeeper (mainnet mode)? | Hanya mengontrol **wallet yang dibuat dari seed itu** (alamat sama di mainnet & testnet). |
| Di mana mnemonic mainnet disimpan? | `~/projects/plx-acton/wallets.toml` di server `dev@100.100.168.168` (gitignored). |

**Nama di Acton (server)** — ini yang dipakai export mnemonic: `plx-deployer-v2`, `plx-treasury`, `plx-lp`, `plx-community`, `plx-marketing`, `plx-vesting-beneficiary`.  
Label `-mainnet` di Tonkeeper hanya nama tampilan; **24 kata = file `wallets.toml` di server**. Panduan lengkap: [`TONKEEPER-CARA-CONNECT.md`](TONKEEPER-CARA-CONNECT.md).

Alamat lengkap: [`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md).

## Deployer vs treasury/LP (baca ini dulu)

Banyak operator mengira “wallet deploy salah” karena saldo PLX **0** setelah import mnemonic deployer. Itu **normal**: deployer hanya admin minter, **bukan** dompet 1B PLX.

| Wallet Acton (nama di server) | PLX | Kapan import ke Tonkeeper |
|--------------|----:|---------------------------|
| `plx-deployer-v2` | **0** | Hanya untuk transaksi admin (drop-admin, metadata) |
| `plx-lp` | 400M | Kelola likuiditas / harga di Ston.fi |
| `plx-treasury` | 250M | Ops / buyback |
| `plx-community` | 200M | Rewards |
| `plx-marketing` | 50M | Kampanye |
| `plx-vesting-beneficiary` | 0→claim | Tim — 100M ada di kontrak vesting dulu |

Mnemonic **testnet** (`plx-deployer-v2`, dll.) **tidak** membuka baris mainnet di tabel atas.

Insiden & gate announce: [`INCIDENT-PLX-SCAM-WALLET.md`](INCIDENT-PLX-SCAM-WALLET.md), [`MAINNET-GO-NO-GO.md`](MAINNET-GO-NO-GO.md).

---

## Opsi A — Hanya melihat PLX (tanpa kontrol treasury)

1. Tonkeeper → **Settings** → **Mainnet**
2. **Add custom token** → paste **minter**:
   ```
   EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
   ```
3. Saldo PLX hanya dari wallet yang sudah Anda import di Tonkeeper.

Untuk saldo treasury/LP tanpa mnemonic: [Tonviewer holders](https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS).

---

## Opsi B — Kontrol penuh (spend) di Tonkeeper

### 1. SSH ke server deploy

```bash
ssh dev@100.100.168.168
cd ~/projects/plx-acton
export PATH="$HOME/.acton/bin:$PATH"
```

### 2. Lihat daftar wallet (aman, tanpa mnemonic)

```bash
bash .scripts/ops/list-mainnet-wallets.sh
acton wallet list
```

Jika hanya nama `plx-treasury` (tanpa `-mainnet`), server belum punya backup mnemonic mainnet — jalankan **langkah 2b**.

### 2b. Verifikasi alamat mainnet dari kunci server

```bash
acton script scripts/print-addrs.tolk --net mainnet
```

Mnemonic **sudah** di `wallets.toml` — tidak perlu wallet baru; export dengan `acton wallet export-mnemonic plx-treasury` (nama Acton tanpa suffix `-mainnet`).

### 3. Export mnemonic **satu per satu** (interaktif)

```bash
acton wallet export-mnemonic plx-treasury
acton wallet export-mnemonic plx-lp
# … ulangi per wallet (nama tanpa suffix -mainnet)
```

Acton meminta konfirmasi sebelum menampilkan 24 kata. **Jangan** log output ke file yang di-commit.

### 4. Import di Tonkeeper (ulangi per wallet)

1. Settings → **Mainnet**
2. **Add wallet** → **Import existing wallet**
3. Masukkan 24 kata wallet tersebut
4. Tambahkan custom jetton minter (Opsi A) jika perlu tampil saldo PLX

Format alamat: Tonkeeper biasa pakai **UQ** (non-bounceable); CLI/docs pakai **EQ** — **akun yang sama**.

---

## Opsi C — Ops script tanpa import 6 wallet (TON Connect)

Hubungkan Tonkeeper yang sudah ada untuk signing script:

```bash
acton script scripts/drop-admin.tolk --net mainnet --tonconnect
```

Cocok untuk transaksi ops sekali-sekali, bukan mengelola semua wallet distribusi.

---

## Backup yang disarankan

- [ ] Export & simpan offline mnemonic setiap wallet mainnet (password manager / paper vault terpisah)
- [ ] Salin encrypted `wallets.toml` ke storage offline (lihat [`MAINNET-CHECKLIST.md`](MAINNET-CHECKLIST.md))
- [ ] Jangan commit mnemonic ke GitHub atau chat

---

## Troubleshooting

| Gejala | Penyebab | Solusi |
|--------|----------|--------|
| Import testnet mnemonic, alamat tidak match treasury docs | Seed berbeda | Export mnemonic wallet `-mainnet` dari server |
| PLX tidak muncul setelah import wallet | Belum add jetton | Custom token → minter address |
| Label SCAM di Tonkeeper | Belum merge ton-assets PR | [`TONKEEPER-SCAM-LABEL-APPEAL.md`](TONKEEPER-SCAM-LABEL-APPEAL.md) |
| `export-mnemonic` tidak interaktif di CI | By design | Jalankan di terminal SSH langsung |
