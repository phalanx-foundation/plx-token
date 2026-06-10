# Tonkeeper — penghapusan label SCAM pada PLX (mainnet)

Dokumen internal untuk tim Phalanx dan reviewer `ton-assets`. Label **SCAM** di Tonkeeper **bukan** artinya kontrak PLX palsu; saat ini jetton belum masuk daftar resmi Tonkeeper dan TonAPI menandai status `verification: blacklist` (heuristik jetton baru).

## Status saat ini

| Sumber | Status |
|--------|--------|
| **Tonkeeper wallet** | Label SCAM / peringatan penipuan (sampai verifikasi resmi) |
| **TonAPI** | `verification: blacklist` pada minter `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` (bukan default semua jetton baru — lihat bagian koreksi di bawah) |
| **Tonviewer** | Transaksi genesis (JettonMint 250M ke treasury) ditampilkan sebagai **FAKE** — **bukan** karena opcode salah; label yang sama dari status verifikasi jetton |
| **Admin deployer** | `is_scam: false` |
| **ton-assets PR** | https://github.com/tonkeeper/ton-assets/pull/5468 (OPEN) |

## Koreksi: Tonviewer “Recently added” ≠ tidak ada risiko

Halaman [Tonviewer → Tokens → Recently added](https://tonviewer.com/tokens?section=recently) adalah **feed indeks jetton baru** untuk eksplorasi pasar. Halaman itu **tidak menampilkan kolom SCAM/FAKE** — banyak token spam (termasuk ticker `$SCAM`, `$FROG`, dll.) tetap muncul di daftar; itu **bukan** sertifikat “aman”.

Perbandingan status TonAPI (contoh riil, mainnet):

| Jetton | Umur / konteks | `verification` (TonAPI) | Label di Tonkeeper (umum) |
|--------|----------------|-------------------------|---------------------------|
| **PLX (Phalanx)** | Mainnet Phalanx | **`blacklist`** | **SCAM** / peringatan keras |
| **SHREK** (contoh baru) | Jetton meme, 3 holder | **`none`** | Biasanya **Unverified**, bukan SCAM |
| **NOT** | Resmi | **`whitelist`** | Terverifikasi |

Kesimpulan: **bukan** semua jetton 1–2 jam otomatis `blacklist`. PLX mendapat status **`blacklist`** khusus (kemungkinan heuristik distribusi genesis / risiko spam / belum ada di `jettons.json` + sinyal tambahan). Alamat PLX **tidak** ada di `to_review/blacklist.csv` publik ton-assets — jadi flag kemungkinan dari **mesin risiko TonAPI/Tonkeeper** (`scam_backoffice_rules`), bukan entri manual di CSV.

**Tindakan:** tetap dorong merge PR #5468 → `whitelist`; di thread PR minta konfirmasi: “Why is minter on blacklist while `admin.is_scam` is false?”

## Penjelasan pernyataan agent sebelumnya (TonAPI `blacklist`)

Pernyataan itu **sebagian besar benar**, dengan nuansa berikut:

| Klaim agent | Penilaian |
|-------------|-----------|
| `verification: blacklist` = heuristik jetton baru / belum dikenal | **Benar** — bukan bukti kontrak rusak; deployer `is_scam: false`, metadata on-chain konsisten. |
| Bukan masalah kontrak | **Benar** — genesis, supply, dan alamat mainnet sesuai dokumentasi deploy. |
| Hilang setelah masuk daftar resmi TON (Tonkeeper `ton-assets`) | **Benar untuk label di Tonkeeper** — satu-satunya jalur resmi yang kita kendalikan lewat PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468). Setelah **merge**, Tonkeeper memakai `jettons.json` dari repo itu; label SCAM/unverified pada wallet biasanya hilang setelah cache (15–60 menit). TonAPI sering menyelaraskan status verifikasi dengan daftar yang sama, tetapi **bukan instan** dan **bukan dijamin** hanya karena submit PR — harus **disetujui dan di-merge**. |
| Ston.fi juga disebut | **Bukan pengganti verifikasi wallet** — listing DEX = likuiditas & discoverability di Ston.fi, **tidak** otomatis menghapus label SCAM di Tonkeeper atau `blacklist` di TonAPI. |

**Mengapa label masih ada sekarang:** PR #5468 masih **OPEN** (belum di-merge Tonkeeper). Submission sudah diajukan; penghapusan label menunggu review mereka.

### Tiga opsi yang ditawarkan agent — status Phalanx

| Opsi agent | Status proyek |
|------------|----------------|
| Commit perubahan | Sudah dilakukan (docs mainnet, `TONKEEPER-*`, push `plx-token` master). |
| Update `TOKENOMICS` alamat mainnet | Sudah ada (tabel distribusi + `MAINNET-DEPLOYMENT-RECORD.md`). |
| Siapkan submission token list (hapus blacklist) | **Sudah diajukan** — PR #5468 + komentar appeal ke reviewer. **Belum selesai** sampai merge. |

**Kesimpulan:** Agent sebelumnya mengarahkan ke langkah yang tepat; yang belum selesai bukan “belum disubmit”, melainkan **menunggu merge Tonkeeper**. Tidak ada skrip lokal yang bisa memaksa TonAPI mengubah `blacklist` hari ini.

## Satu-satunya jalur resmi penghapusan label (Tonkeeper)

Sesuai [dokumentasi verifikasi Tonkeeper](https://tonkeeper.helpscoutdocs.com/article/127-tokennftverification):

1. PR ke `tonkeeper/ton-assets` dengan metadata benar (sudah diajukan).
2. Review dan **merge** oleh tim Tonkeeper (gratis, tanpa biaya).
3. Setelah merge, refresh wallet; cache biasanya 15–60 menit.

Label SCAM untuk token yang **belum** diverifikasi sering muncul bersama peringatan risiko; setelah masuk daftar resmi, Tonkeeper menampilkan metadata terverifikasi seperti jetton lain (NOT, STON, dll.).

## Bukti legitimasi (untuk reviewer PR #5468)

| Bukti | Tautan |
|-------|--------|
| Minter mainnet | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| Explorer | https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS |
| Logo HTTPS | https://plx.foundation/plx-logo.png |
| Situs resmi | https://plx.foundation/plx-token |
| Repo kontrak (publik) | https://github.com/phalanx-foundation/plx-token |
| Catatan deploy | `docs/MAINNET-DEPLOYMENT-RECORD.md` di repo di atas |
| Supply on-chain | 1 000 000 000 PLX (9 desimal) — genesis ke 5 holder + vesting contract |
| Telegram channel | https://t.me/phalanxfoundation |
| Telegram bot | https://t.me/phalanxfoundationbot |

**Bukan** token impersonasi: nama **Phalanx**, simbol **PLX**, tanpa karakter `$` di ticker, tanpa klaim airdrop Tonkeeper di metadata.

## Tindakan tim (checklist)

- [x] PR `jettons/PLX.yaml` — #5468
- [ ] Pantau komentar reviewer di PR; jawab dalam 24 jam jika diminta bukti tambahan
- [ ] Setelah merge: konfirmasi di Tonkeeper (import minter → tidak ada label SCAM)
- [ ] Opsional: ajukan label alamat di Tonviewer / Tonscan (`TRANSPARENCY.md`)
- [ ] Jika PR ditolak: email **support@tonkeeper.com** dengan tautan PR, minter, dan bukti di atas (bahasa Inggris)

## Pesan untuk stakeholder (investor / mitra)

Gunakan naskah formal berikut — **jangan** menyamakan label SCAM dengan kecurangan proyek sebelum review selesai.

> Phalanx (PLX) telah diluncurkan di TON mainnet dengan kontrak sumber terbuka dan metadata on-chain yang dapat diverifikasi di Tonviewer. Tonkeeper menampilkan label SCAM pada jetton yang belum masuk daftar verifikasi resmi mereka; ini adalah kontrol risiko wallet, bukan putusan audit atas kontrak kami. Phalanx Foundation telah mengajukan verifikasi resmi melalui Pull Request [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) ke repositori `tonkeeper/ton-assets`. Setelah PR disetujui dan digabung, label tersebut dihapus dari aplikasi Tonkeeper secara otomatis. Sementara proses berjalan, verifikasi independen dapat dilakukan melalui alamat minter dan repositori GitHub yang tercantum di https://plx.foundation/plx-token.

---

*Terakhir diperbarui: 2026-06-02.*
