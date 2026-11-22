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

Jumlah test yang benar adalah **185 test di 21 file**. Angka "60 tests"
maupun "72+ tests" yang masih muncul di sebagian dokumen lama sudah **usang**
dan tidak boleh dipakai sebagai acuan review.

## Gerbang non-blocking (continue-on-error)

| # | Gerbang | Kondisi saat ini | Alasan tidak memblokir |
|---|---------|------------------|------------------------|
| N1 | `acton fmt --check` | masih ada diff format | kosmetik; sudah dirapikan bertahap, sisa diff tidak mengubah semantik |
| N2 | `acton check` (lint) | ~105 warning gaya | gaya penulisan, bukan bug fungsional |

Keduanya berstatus `continue-on-error` di workflow `Contracts CI`, sehingga
tidak menghalangi merge maupun rilis. Target jangka menengah: menurunkan
warning secara bertahap lalu menaikkan `fmt --check` menjadi gerbang wajib.

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
