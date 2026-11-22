# CI Gate Verification — PLX Token

Dokumen ini mencatat hasil verifikasi ulang gerbang CI pada workspace kanonik,
beserta batas jelas antara yang **blocking** dan yang **non-blocking**.

## Workspace kanonik

| Item | Nilai |
|------|-------|
| Path | `/home/dev/plx-token` |
| Branch | `master` |
| Toolchain | `acton 1.1.0` |
| Workspace exists | ya (diverifikasi langsung di mesin) |

Catatan: laporan "workspace tidak ditemukan" yang pernah muncul adalah
**false negative** dari scanner. Path di atas adalah satu-satunya lokasi kanonik.
Tooling apa pun yang melakukan scan wajib memakai path ini agar kejadian yang
sama tidak terulang.

## Gerbang blocking

| # | Gerbang | Perintah | Hasil | Status |
|---|---------|----------|-------|--------|
| G1 | Build | `acton build` | exit 0 | PASS |
| G2 | Test suite | `acton test` | 185/185 passed di 21 file, exit 0 | PASS |
| G3 | Metadata TEP-74 | validasi metadata | valid | PASS |
| G4 | Contracts CI (GitHub Actions) | run `44994560000` | success (27s) | PASS |
| G5 | Format | `acton fmt --check` | exit 0, diff nol | PASS (blocking sejak `e69e909`) |

HEAD saat verifikasi: `9e70e66`, sinkron penuh dengan `origin/master`.

Jumlah test yang benar adalah **185 test di 21 file**. Angka "60 tests"
maupun "72+ tests" yang masih muncul di sebagian dokumen lama sudah **usang**
dan tidak boleh dipakai sebagai acuan review.

## Gerbang format (promosi dari non-blocking)

| # | Gerbang | Kondisi | Status |
|---|---------|---------|--------|
| G5 | `acton fmt --check` | "All files are properly formatted", exit 0 tanpa perubahan worktree | PASS — **blocking** |

Diff format sudah nol sejak commit `5137831`, sehingga gate ini dinaikkan
menjadi wajib di `e69e909` (tidak lagi `continue-on-error`). Kalau step ini
merah, jalankan `acton fmt` lokal lalu commit hasilnya — jangan menurunkannya
kembali ke non-blocking.

## Gerbang non-blocking (continue-on-error)

| # | Gerbang | Kondisi saat ini | Alasan tidak memblokir |
|---|---------|------------------|------------------------|
| N1 | `acton check` (lint) | 18 warning gaya | gaya penulisan, bukan bug fungsional |

Rincian warning per kode aturan (sesuai `acton check` terkini, bukan angka
lama 105 yang kini usang):

| Kode | Jumlah | Arti |
|------|--------|------|
| E028 | 8 | throw code sebaiknya memakai `Errors.<Name>` |
| E016 | 6 | send dengan mode berbahaya perlu komentar keselamatan |
| E019 | 3 | pembagian sebelum perkalian berpotensi kehilangan presisi |
| E005 | 1 | import tidak terpakai |

Tiga di antaranya bernilai fungsional — E016 dan E019 menyentuh keamanan
pengiriman pesan dan presisi aritmetika — sehingga bukan sekadar kosmetik.
Urutan penanganan: E019 → E016 → E028 → E005. Setelah tiap batch, jalankan
`acton build` + `acton test`; suite harus tetap 185/185.

## Kebijakan penafsiran hasil

- Gate yang dinyatakan **HIJAU** harus disertai bukti eksekusi nyata (exit code
  dan jumlah test), bukan asumsi atau salinan laporan sebelumnya.
- Build dan test harus dijalankan pada **working tree yang akan dirilis**,
  termasuk jika ada perubahan yang belum di-commit.
- Selisih antara jumlah test yang dilaporkan dan yang benar-benar berjalan
  diperlakukan sebagai cacat dokumentasi, bukan cacat kode — tetapi tetap
  wajib diperbaiki sebelum review eksternal.

## Rujukan

- Checklist rilis: `docs/MAINNET-GO-NO-GO.md` (item C1 memakai angka 185/185)
- Workflow: `.github/workflows/contracts.yml`
