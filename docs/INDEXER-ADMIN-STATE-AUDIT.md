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

Bukan soal jenis metadata, dan **bukan** soal ada/tidaknya alamat admin. Kolom itu memetakan
**flag `mintable`** dari `toncenter v3 /jetton/masters`.

Bukti pemetaan — Tonscan menulis **Yes** untuk ketiganya, dan ketiganya `toncenter_v3 = true`:

| Token | flag on-chain (`stack[1]`) | TonAPI decoded | toncenter v3 | Tonscan |
|-------|---------------------------|----------------|--------------|---------|
| **PLX** | `0x0` (false) | `false` | **`true`** ← basi | Yes |
| **NOT** | `-0x1` (true) | `true` | `true` | Yes |
| **USDT** | `-0x1` (true) | `true` | `true` | Yes |

Dua sebab berbeda menghasilkan tampilan yang sama:

- **NOT** → **akurat**. Kontrak Notcoin memang tetap mengembalikan `mintable = -1` meski
  admin sudah di-set ke burn (`0:0000…0000`). Itu kekhasan kontrak mereka, bukan bug indexer.
- **PLX** → **salah**. Flag on-chain `0x0`, tetapi record toncenter masih `true` karena beku
  sebelum revoke.

Karena satu nilai "Yes" bisa berarti akurat **atau** basi, kolom ini **tidak dapat dipakai**
untuk menyimpulkan status revoke token mana pun.

## Bukti record basi

| Token | admin di toncenter v3 | `last_transaction_lt` | Keterangan |
|-------|----------------------|----------------------|------------|
| **PLX** (admin null) | deployer (basi) | `81006661000012` | beku sebelum revoke 27 Aug |
| `EQBwLccX…UOQqW` (admin null) | `0:18AA75E0…` (basi) | `82520593000008` | pola identik |
| USDT (admin aktif) | admin benar | `99991183000015` | segar |
| NOT (admin burn) | kosong di toncenter; `0:0000…0000` di DYOR | `99816265000012` | segar |

Pembeda utamanya bukan "admin kosong", melainkan **transisi admin → null**. NOT memakai
**burn address** (bukan null) sehingga indexer tetap memprosesnya; PLX memakai null sehingga
record membeku. Ini menguatkan keputusan toolkit memakai burn address untuk deploy baru.

Dua jetton dengan admin `null` sama-sama **berhenti diperbarui** di titik transisi, sedangkan
token dengan admin aktif tetap segar. Ini kelas bug yang sama seperti yang sudah TonAPI perbaiki.

## Bukti terkuat: dua tabel toncenter tidak sinkron

Dalam **satu API yang sama**, state akun segar tetapi baris jetton master beku:

| Endpoint toncenter v3 | `last_transaction_lt` | Kondisi |
|-----------------------|----------------------|---------|
| `/accountStates` | `99603236000013` | **segar** — sudah mencakup revoke 27 Aug |
| `/jetton/masters` | `81006661000012` | **basi** — berhenti sebelum revoke |

Ini menutup kemungkinan "node belum sinkron". Yang gagal spesifik jalur parsing
**jetton master** pada admin `null`.

## Verifikasi source: sudah ada, salah alamat

TonAPI `/inspect` mengembalikan **seluruh source Tolk PLX**, jadi kontrak memang terverifikasi
dan Tonviewer menampilkannya. Label "Unverified contract" di Tonscan berasal dari registry
**DYOR** (`verification: JVS_NONE`), bukan dari TON source verifier — jadi submit ulang ke
verifier tidak menyelesaikan apa pun.

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
| 3 | ~~Verifikasi source di Tonscan~~ — **tidak perlu**, source sudah terverifikasi; label berasal dari DYOR | — |
| 4 | Jangan pakai Tonscan `Mutable` sebagai bukti revoke | agent + docs |

Draft pesan siap kirim: [`INDEXER-REFRESH-REQUESTS.md`](INDEXER-REFRESH-REQUESTS.md).

## Cara benar memastikan revoke (UI)

Tonviewer → alamat minter:

- riwayat memuat opcode **`0x7431f221`** (`DropMinterAdmin`) pada 27 Aug 10:13
- tidak ada `JettonMint` setelah tanggal itu
- badge centang biru = verifikasi TonAPI aktif

Untuk PLX status ini **permanen**; tidak perlu dicek berulang.
