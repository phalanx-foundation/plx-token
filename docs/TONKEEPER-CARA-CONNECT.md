# Cara connect wallet PLX ke Tonkeeper (Anda punya datanya di server)

> **PENTING — baca dulu jika alamat Tonkeeper tidak cocok setelah paste 24 kata:**  
> [`TONKEEPER-ALAMAT-TIDAK-COCOK.md`](TONKEEPER-ALAMAT-TIDAK-COCOK.md)  
> Impor mnemonic saja **tidak cukup** di HP; harus pakai wallet **W5** (bukan V4R2 default).

**Anda tidak perlu “data wallet baru”.** Enam dompet PLX dibuat di server Ubuntu dengan Acton; **24 kata disimpan di** `~/projects/plx-acton/wallets.toml` (file itu yang “datanya”).

Yang membingungkan: **nama di Tonkeeper** (`plx-treasury-mainnet`) vs **nama di Acton** (`plx-treasury`) — **mnemonic-nya satu sumber**, di server.

---

## Fakta teknis (W5 / v5r1)

| | Testnet (Tonkeeper “Testnet Account”) | Mainnet (Tonkeeper wallet biasa) |
|--|----------------------------------------|----------------------------------|
| **24 kata** | Sama (dari server) | **Sama** |
| **Alamat tampil** | `kQ...` | `UQ...` / `EQ...` (**beda** dari kQ) |
| **PLX genesis** | Saldo testnet | **400M / 250M / … di mainnet** |

Satu mnemonic **bukan** “satu alamat di semua network” untuk wallet W5 — tapi **Anda tetap mengontrol mainnet** dengan mnemonic yang sama, di-import sebagai **wallet mainnet** di Tonkeeper.

---

## Langkah 1 — Lihat alamat mainnet dari kunci di server

Di PC Windows (PowerShell):

```powershell
ssh dev@100.100.168.168
cd ~/projects/plx-acton
export PATH="$HOME/.acton/bin:$PATH"
acton script scripts/print-addrs.tolk --net mainnet
```

Harus cocok dengan docs (contoh):

| Nama Acton | Alamat mainnet (EQ) |
|------------|---------------------|
| plx-deployer-v2 | `EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj` |
| plx-treasury | `EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX` |
| plx-lp | `EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH` |
| plx-community | `EQD1XDv0Awjx0GUVv6YQYYnvEmjcKJ9iEBjvtHPM2nWML-q9` |
| plx-marketing | `EQDB9yVhkPvEhMFo90fqHWzqYj2mESAlwObMbA6LX7fETtN6` |
| plx-vesting-beneficiary | `EQB5_ndfsF6gSuMDYYA4Uq2R26jPRzEsvFK-glI9VwbzLdYH` |

---

## Langkah 2 — Ambil 24 kata (connect mnemonic)

**Harus di terminal SSH langsung** (Acton minta konfirmasi; agent otomatis tidak bisa).

Ulangi **6 kali** (ganti nama wallet):

```bash
acton wallet export-mnemonic plx-deployer-v2
acton wallet export-mnemonic plx-treasury
acton wallet export-mnemonic plx-lp
acton wallet export-mnemonic plx-community
acton wallet export-mnemonic plx-marketing
acton wallet export-mnemonic plx-vesting-beneficiary
```

Salin 24 kata ke catatan aman (kertas / password manager). **Jangan** kirim ke chat, email, atau GitHub.

Opsional QR di PC (setelah export):

```powershell
cd "D:\DATA PRIVACY\WALLET-PLX"
py -3.12 plx-community.py plx-treasury-mainnet.png
# paste 24 kata treasury → Enter → scan di HP → hapus PNG
```

---

## Langkah 3 — Import di Tonkeeper (mainnet)

Untuk **setiap** dompet (treasury, lp, …):

1. Buka Tonkeeper → pastikan **bukan** mode Testnet (untuk PLX mainnet).
2. **Add wallet** → **Import existing wallet** (Impor dompet).
3. Pilih **24 words** → paste 24 kata dari langkah 2.
4. Selesai → cek alamat **UQ** di profil wallet → harus cocok dengan tabel EQ di atas (format beda, akun sama).

**Deployer saja:** jika Anda sudah punya wallet `UQBfYLpq…` dengan TON — itu **sudah** `plx-deployer-v2` mainnet. Tidak perlu import deployer lagi kecuali ingin di HP kedua.

---

## Langkah 4 — Tampilkan saldo PLX

Setelah wallet mainnet ter-import:

1. Settings / Assets → **Add custom token** (mainnet).
2. Paste **minter** (bukan alamat wallet Anda):

   ```
   EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
   ```

3. Buka wallet **treasury** → harus tampil ~250M PLX (setelah jetton ditambahkan).

| Wallet di Tonkeeper | PLX yang diharapkan |
|---------------------|---------------------|
| Deployer | **0** (normal) |
| LP | 400.000.000 |
| Treasury | 250.000.000 |
| Community | 200.000.000 |
| Marketing | 50.000.000 |
| Vesting beneficiary | 0 sampai claim (100M di kontrak vesting) |

---

## Kalau “tidak punya data”

| Situasi | Solusi |
|---------|--------|
| Tidak pernah export mnemonic | Langkah 2 di SSH — data ada di `wallets.toml` server |
| Hanya punya deployer di HP | Export **lima** wallet lain dari server (treasury, lp, …) |
| Import tapi PLX 0 | Belum add custom jetton minter (langkah 4) |
| Import di Testnet Account | Salah mode — ulang import sebagai **wallet mainnet** |
| Lupa password SSH server | Gunakan akses `dev@100.100.168.168` yang sama seperti saat deploy |

**Tanpa** 24 kata dari server, **tidak ada** cara menggerakkan 1B PLX di treasury/LP — itu kunci kripto, bukan “connect API”.

---

## Ops: transaksi tanpa import 6 wallet ke HP

```bash
acton script scripts/drop-admin.tolk --net mainnet --tonconnect
```

Tonkeeper yang sudah ada scan QR TON Connect — cocok untuk **satu** tx admin, bukan mengganti import treasury/LP.

---

## Label SCAM

Bukan masalah mnemonic. Ikuti [`TONKEEPER-EMAIL-ESCALATION.md`](TONKEEPER-EMAIL-ESCALATION.md) + PR ton-assets #5468.
