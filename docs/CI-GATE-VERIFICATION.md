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
| G1 | Build | `acton build` | exit 0 ("Compiling contracts", Finished) | PASS |
| G2 | Test suite | `acton test` | 185/185 passed di 21 file, exit 0 | PASS |
| G3 | Metadata TEP-74 | validasi metadata | valid | PASS |
| G4 | Contracts CI (GitHub Actions) | run `45027745928` (sha `55e54b6`) | success | PASS |
| G5 | Format | `acton fmt --check` | "All files are properly formatted", exit 0 | PASS (blocking) |

Verifikasi ulang terakhir: **22 Nov 2026** (waktu Jakarta). Diukur di working
tree HEAD `287e345` — G1, G2, G5, dan G3 dijalankan langsung di mesin ini pada
commit tersebut, bukan diwarisi dari laporan sebelumnya. G4 merujuk run GitHub
Actions terakhir yang sudah selesai.

Gate G3 — rincian agar tidak ditafsirkan berlebihan: `metadata/phalanx-metadata.json`
valid JSON dengan `name=Phalanx`, `symbol=PLX`, `decimals=9`, `image=https://plx.foundation/plx-logo.png`,
sehingga **syarat TEP-74 terpenuhi** (field wajib ada dan bertipe benar) dan
metadata on-chain dapat dipakai apa adanya. Namun `image_ipfs_uri` masih kosong:
CID IPFS belum di-pin (`metadata/plx-logo-ipfs.json` masih `cid: ""`). Ini
**bukan** pelanggaran gerbang, melainkan item rilis yang harus selesai sebelum
listing — jalankan `scripts/pin-plx-logo-ipfs.py` lalu ganti `image` ke
`ipfs://CID`. Jangan menandai G3 PASS sebagai "metadata sudah final on-chain"
tanpa menyebut catatan ini.

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
| N1 | `acton check` (lint) | 10 lokasi warning unik, exit 0 | gaya penulisan, bukan bug fungsional |

Angka yang benar adalah **10 lokasi warning unik** (`acton check` exit 0),
terukur ulang 22 Nov 2026 pada HEAD `287e345`. Angka "105" dan "18 warning"
yang muncul di laporan sebelumnya sama-sama usang: 105 adalah hitungan lama
sebelum pembersihan import, sedangkan 18 berasal dari menghitung baris
keluaran `acton check` yang menyebut lokasi yang sama lebih dari sekali
(sweep berlapis). Cara mengukur yang benar adalah menghitung `file:baris:kolom`
unik, bukan jumlah baris log. Output mentah `acton check` saat ini berisi 21
baris kata "warning", jadi jangan pakai `grep -c warning` — itu bukan jumlah
temuan; hitung pola `path/file.tolk:baris:kolom` lalu `sort -u`.

Rincian per kode aturan (terukur pada `acton check` di working tree ini):

| Kode | Jumlah | Arti |
|------|--------|------|
| S005 | 3 | nama message/struct belum sesuai konvensi |
| E019 | 3 | pembagian sebelum perkalian berpotensi kehilangan presisi |
| E028 | 2 | throw code sebaiknya memakai `Errors.<Name>` |
| E016 | 2 | send dengan mode berbahaya perlu komentar keselamatan |

Sebaran per berkas:

| Berkas | Kode |
|--------|------|
| `contracts/AntiWhaleJettonWallet.tolk` | E016 ×1, E028 ×2 |
| `contracts/FeeJettonWallet.tolk` | E016 ×1 |
| `contracts/CustomStakingParams.tolk` | E019 ×1 |
| `contracts/PlxStaking.tolk` | E019 ×1 |
| `contracts/TokenStaking.tolk` | E019 ×1 |
| `contracts/MidasHandEscrow.tolk` | S005 ×1 |
| `scripts/send-ton.tolk` | S005 ×1 |
| `scripts/treasury-sweep.tolk` | S005 ×1 |

Dua kode bernilai fungsional — E016 dan E019 menyentuh keamanan pengiriman
pesan dan presisi aritmetika — sehingga bukan sekadar kosmetik. Urutan
penanganan: E019 → E016 → E028 → S005. Setelah tiap batch, jalankan
`acton build` + `acton test`; suite harus tetap 185/185.

Catatan E005 (import tidak terpakai) sudah **nol** sejak commit `9e70e66`,
jadi tidak lagi masuk daftar ini.

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
