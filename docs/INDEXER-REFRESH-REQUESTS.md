# Permintaan refresh indexer — PLX (siap kirim)

Turunan dari [`INDEXER-ADMIN-STATE-AUDIT.md`](INDEXER-ADMIN-STATE-AUDIT.md).
Semua angka di bawah sudah diverifikasi 2026-08-29.

**Minter:** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`

## Bukti kunci (dipakai di kedua laporan)

Dalam **satu API toncenter yang sama**, dua tabel tidak sinkron:

| Endpoint toncenter v3 | `last_transaction_lt` | Kondisi |
|-----------------------|----------------------|---------|
| `/accountStates` | `99603236000013` | **segar** (mencakup revoke 27 Aug) |
| `/jetton/masters` | `81006661000012` | **basi** (berhenti sebelum revoke) |

Akibatnya `/jetton/masters` masih melaporkan:

- `admin_address: 0:5F60BA6A…1A9E` — deployer, admin **sebelum** revoke
- `mintable: true` — padahal flag on-chain `0x0`

Get-method tidak error di provider mana pun (`exit_code: 0`), jadi ini bukan kontrak rusak.

---

## 1. toncenter / TON Index — TERKIRIM

**Issue:** [toncenter/ton-indexer#447](https://github.com/toncenter/ton-indexer/issues/447)
(dibuka 2026-08-29, OPEN, atas persetujuan user memakai akun pribadi).

Isi issue memuat tabel `last_transaction_lt` lintas 4 token dan bukti `/accountStates`
vs `/jetton/masters`. Teks lengkap arsip di bawah.

**Repo:** https://github.com/toncenter/ton-indexer

> **Title:** `jetton_masters` row not updated after admin revoke (admin stays stale, mintable wrong)
>
> **Body:**
>
> Jetton master `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` executed a drop-admin
> (opcode `0x7431f221`) on 2026-08-27, setting the admin to null. On-chain `get_jetton_data`
> now returns `mintable = 0` with an empty admin slot, and the get-method itself succeeds
> (`exit_code: 0` on both toncenter `runGetMethod` and TonAPI).
>
> `/api/v3/jetton/masters` still reports the pre-revoke state:
>
> - `admin_address: 0:5F60BA6A44DA788D5BDF7D86FAB9C91C1953364B917527CA6AFA99C5B0DD1A9E`
> - `mintable: true`
> - `last_transaction_lt: 81006661000012`
>
> Meanwhile `/api/v3/accountStates` for the same address is current with
> `last_transaction_lt: 99603236000013`, so the account state advanced but the
> `jetton_masters` row did not.
>
> A second master with a null admin shows the same frozen pattern
> (`EQBwLccXri43Tm5MetSghCB6bKaO2AygLZtXZgoN3x5UOQqW`,
> `last_transaction_lt: 82520593000008`), while masters with an active admin stay fresh.
> TonAPI hit the same class of bug and shipped a workaround, so this looks like the
> null-admin branch failing during jetton-master parsing rather than a per-token issue.
>
> Downstream impact: explorers reading this endpoint show the token as still mintable by
> the old admin, which is the opposite of the on-chain state.

**Catatan identitas:** user menyetujui pemakaian akun pribadi `KelvinHernata` karena
issue [opentonapi#963](https://github.com/tonkeeper/opentonapi/issues/963) sudah dibuka dari
akun yang sama.

---

## 2. DYOR / Tonscan

Tonscan mengambil data jetton dari `jetton-index.tonscan.org/public-dyor/...`, jadi
perbaikan harus lewat DYOR.

**Kanal:** [@dyorsupportbot](https://t.me/dyorsupportbot) (support) · [@dyorapi](https://t.me/dyorapi) (dev/API)
**Kirim dari akun Telegram user** — agent tidak bisa mengirim Telegram.

### Ini data DYOR sendiri, bukan cache Tonscan

`https://api.dyor.io/v1/jettons/{minter}` (API resmi, bukan proxy) mengembalikan hal yang sama:

| Field | Nilai DYOR | Seharusnya |
|-------|-----------|-----------|
| `admin.address` | `0:5f60ba6a…dd1a9e` (deployer) | kosong |
| `mintable` | `true` | `false` |
| `verification` | `JVS_NONE` | minimal `JVS_APPROVED` |
| `trustScore` | `0` | — |

DYOR **menangani burn address dengan benar** — record NOT menunjukkan
`admin: 0:0000…0000` dan `mintable: false`. Yang gagal khusus admin `null`, sama seperti
toncenter dan TonAPI sebelum diperbaiki.

### Pesan

> Hi! Requesting a data refresh for PLX `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`.
>
> The admin was revoked on 2026-08-27 (drop-admin, opcode `0x7431f221`), so on-chain
> `get_jetton_data` returns `mintable = 0` with an empty admin slot. TonAPI already reflects
> this (`mintable: false`, `verification: whitelist`).
>
> `api.dyor.io/v1/jettons/EQCba…` still returns the pre-revoke admin
> `0:5f60ba6a44da788d5bdf7d86fab9c91c1953364b917527ca6afa99c5b0dd1a9e` with `mintable: true`,
> so Tonscan shows the token as still mintable by the old admin.
>
> It looks specific to a **null** admin rather than a burn address — your Notcoin record
> handles `0:0000…0000` correctly with `mintable: false`. The upstream
> `toncenter /api/v3/jetton/masters` row is stale for the same reason
> (filed as toncenter/ton-indexer#447), so a refresh may need to re-read the contract directly.
>
> Separately, I'd like to complete jetton verification — currently `JVS_NONE`. Happy to
> provide whatever you need.

---

## 3. Verifikasi source — sudah beres, jangan diulang

TonAPI `/v2/blockchain/accounts/{minter}/inspect` **sudah** mengembalikan seluruh source
Tolk PLX (`JettonMinter.tolk`, `storage.tolk`, `messages.tolk`, dll). Itu sebabnya Tonviewer
menampilkan source.

Label "Unverified contract" di Tonscan berasal dari registry DYOR (`JVS_NONE`), **bukan**
dari TON source verifier. Jadi tidak perlu submit ulang ke verifier — tangani lewat butir 2.

---

## Yang tidak akan diperbaiki oleh butir mana pun

| Item | Nilai | Syarat sebenarnya |
|------|-------|------------------|
| `TonAPI /v2/rates` USD | `0` | LP ≥ ~100 TON **dan** holders ≥ 100 |
| DexScreener | `pairs: null` | ada aktivitas swap di pool |

Keduanya butuh modal/aktivitas, bukan perbaikan indexer.
