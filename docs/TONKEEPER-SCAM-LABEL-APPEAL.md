# Tonkeeper — penghapusan label SCAM pada PLX (mainnet)

Dokumen internal untuk tim Phalanx dan reviewer `ton-assets`. Label **SCAM** di Tonkeeper **bukan** artinya kontrak PLX palsu; saat ini jetton belum masuk daftar resmi Tonkeeper dan TonAPI menandai status `verification: blacklist` (heuristik jetton baru).

## Status saat ini

| Sumber | Status |
|--------|--------|
| **Tonkeeper wallet** | Label SCAM / peringatan penipuan (sampai verifikasi resmi) |
| **TonAPI** | `verification: blacklist` pada minter `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| **Admin deployer** | `is_scam: false` |
| **ton-assets PR** | https://github.com/tonkeeper/ton-assets/pull/5468 (OPEN) |

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
| Telegram resmi | https://t.me/phalanxfoundationbot |

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
