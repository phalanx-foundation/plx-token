# Tampilkan PLX di Tonkeeper (2 menit)

Wallet Anda **sudah benar** (W5, alamat `UQ…` cocok deploy). Yang sering kurang: **jetton belum ditambahkan**.

## Langkah

1. Pastikan **mainnet** (bukan Testnet Account untuk PLX genesis).
2. Buka wallet (mis. **PLX Treasury**).
3. **Add asset** / **Custom token** / **Add jetton**.
4. Paste **minter** (bukan alamat wallet Anda):

   ```
   EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
   ```

5. Simpan → saldo PLX harus muncul (Treasury ~250M, LP ~400M, dll.).

## Label SCAM — add custom token TIDAK menghapusnya

| Aksi | Menghapus SCAM? |
|------|-----------------|
| Add custom token (langkah di atas) | **Tidak** — hanya menampilkan saldo PLX |
| Merge PR ton-assets [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) | **Ya** — satu-satunya jalur resmi |

Selama PR belum merge, label SCAM bisa tetap muncul meski saldo PLX sudah benar. Konteks lengkap: [`SCAM-LABEL-HAPUS.md`](SCAM-LABEL-HAPUS.md). Email: [`TONKEEPER-EMAIL-ESCALATION.md`](TONKEEPER-EMAIL-ESCALATION.md).

## Tanpa Tonkeeper

[STATUS-MAINNET.md](STATUS-MAINNET.md) — link Tonviewer per wallet.
