# Indexer admin-state audit — PLX post drop-admin

Audit 2026-08-29. Tujuan: memastikan setiap indexer melaporkan status admin PLX dengan benar
setelah `DropMinterAdmin` (opcode `0x7431f221`) dieksekusi 2026-08-27.

**Minter:** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` (`0:9b69426a…e6755`)

## Kebenaran on-chain (acuan)

Dua provider get-method sepakat, dan keduanya sukses:

| Sumber | `exit_code` | admin slot | `mintable` |
|--------|------------|-----------|-----------|
| toncenter `runGetMethod` | 0 | `tvm.list` kosong | 0 |
| TonAPI `/methods/get_jetton_data` | 0 | `null` | 0 |

Kontrak **tidak** bermasalah. Admin kosong permanen; tidak ada yang bisa mint lagi.

## Hasil per indexer

| Indexer | admin dilaporkan | `mintable` | Sesuai on-chain? |
|---------|-----------------|-----------|-----------------|
| **TonAPI** `/v2/jettons/` | (kosong) | `false` | **YA** |
| **toncenter v3** `/jetton/masters` | `0:5F60BA6A…1A9E` (deployer) | `true` | **TIDAK** |
| **Tonscan / DYOR** `jetton-index` | `EQBfYLpq…N0anklj` (deployer) | `true` | **TIDAK** |

`0:5f60ba6a…dd1a9e` = **plx-deployer-v2**, admin **sebelum** revoke.

## Kenapa Tonscan menulis "Mutable: Yes"

Bukan soal jenis metadata. Rantainya:

1. `JettonInfo.vue` merender `Mutable` dari prop `is_mutable`
2. Prop itu berasal dari record jetton yang di-fetch `getJettonInfo()`
3. Sumber datanya `jetton-index.tonscan.org` (DYOR) + `toncenter v3`
4. Keduanya **masih menyimpan admin lama**, sehingga jetton dianggap mutable

Jadi "Mutable: Yes" adalah **konsekuensi data indexer yang basi**, bukan indikator metadata.

## Bukti record basi

| Token | admin di toncenter v3 | `last_transaction_lt` | Keterangan |
|-------|----------------------|----------------------|------------|
| **PLX** (admin null) | deployer (basi) | `81006661000012` | beku sebelum revoke 27 Aug |
| `EQBwLccX…UOQqW` (admin null) | `0:18AA75E0…` (basi) | `82520593000008` | pola identik |
| USDT (admin aktif) | admin benar | `99991183000015` | segar |
| NOT | kosong | `99816265000012` | segar; kontraknya memang balikkan `mintable=-1` |

Dua jetton dengan admin `null` sama-sama **berhenti diperbarui** di titik transisi, sedangkan
token dengan admin aktif tetap segar. Ini kelas bug yang sama seperti yang sudah TonAPI perbaiki.

## Dampak

- Tonscan menampilkan PLX **seolah masih bisa di-mint oleh deployer** — menyesatkan calon holder
- Klaim "admin revoked" di materi resmi bisa dianggap tidak konsisten dengan explorer
- `trustScore: 0` dan `verification: JVS_NONE` di DYOR memperkuat kesan negatif

## Catatan penting: harga sudah ada di luar TonAPI

Record DYOR/Tonscan memuat harga, berbeda dari `TonAPI /v2/rates` yang masih `0`:

| Field | Nilai |
|-------|-------|
| `priceUsd` | ~`$0.000141` |
| `mcap` / `fdmc` | ~`$140,569` |
| `liquidityUsd` | ~`$26.79` |
| `holdersCount` | 9 |

Artinya "harga PLX hilang" **tidak berlaku menyeluruh** — yang belum ada khusus nilai USD di
Tonkeeper, karena wallet itu terikat `TonAPI /v2/rates` (gate LP ≥ ~100 TON + holders ≥ 100).

## Tindakan

| # | Aksi | Pemilik |
|---|------|---------|
| 1 | Laporkan record basi ke toncenter / TON Index | manusia |
| 2 | Minta DYOR refresh admin + `mintable` PLX | manusia |
| 3 | Verifikasi source PLX di Tonscan (`verification tool`) — Tonviewer sudah verified | manusia |
| 4 | Jangan pakai Tonscan `Mutable` sebagai bukti revoke | agent + docs |

## Cara benar memastikan revoke (UI)

Tonviewer → alamat minter:

- riwayat memuat opcode **`0x7431f221`** (`DropMinterAdmin`) pada 27 Aug 10:13
- tidak ada `JettonMint` setelah tanggal itu
- badge centang biru = verifikasi TonAPI aktif

Untuk PLX status ini **permanen**; tidak perlu dicek berulang.
