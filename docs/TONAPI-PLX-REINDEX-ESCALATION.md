# TonAPI escalation — PLX jetton catalog (INTERNAL)

**JANGAN** buka GitHub issue publik dari akun pribadi. Gunakan support TonAPI / email org / bot `phalanx-foundation` saja.

## Symptom

`GET /v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` → 404 entity not found

## On-chain (toncenter `get_jetton_data`)

- supply OK, mintable `0`
- **admin stack = empty tvm.list** (addr_none / null) — akar “beginParse null”; tidak bisa diubah lagi tanpa admin
- metadata Phalanx/PLX cell OK; account active

## Request (template anonim)

Force reindex jetton master `0:9b69426a…e6755` despite empty admin encoding after revoke. Balances/holders/metadata still on-chain.

## Official self-serve API tried (2026-08-28)

Docs: `POST https://tonapi.io/v2/accounts/{account_id}/reindex` (“Update internal cache for a particular account”). Auth: `Authorization: Bearer $TONAPI_KEY`.

| Step | Target | Result |
|------|--------|--------|
| Baseline | `GET /v2/jettons/EQCba…` | **404** |
| Baseline | `GET /v2/accounts/EQCba…` | **200** |
| Baseline | `GET /v2/jettons/EQCba…/holders` | **200** |
| Reindex | minter `EQCba…` | POST **200** |
| Poll ×10 (~30s) | `/v2/jettons/EQCba…` | masih **404** |
| Reindex | Treasury, Community, LP, Marketing, Vesting, Deployer | semua POST **200** |
| Poll ×8 | `/v2/jettons/EQCba…` | masih **404** |

Kesimpulan: reindex akun **tidak** recreate baris katalog jetton. Lanjut [@tonapi_bot](https://t.me/tonapi_bot) + issue [#963](https://github.com/tonkeeper/opentonapi/issues/963).

## Root cause dikonfirmasi TonAPI (2026-08-28)

TonAPI Tech via Telegram:

> Yes, indeed. Null is not valid value for the admin field (according to TEP-74). Slice is expected.
> This is second time I see this (…`EQBwLccXri43Tm5MetSghCB6bKaO2AygLZtXZgoN3x5UOQqW` has same problem).
> Looks like its time for a workaround. I'll take a look very soon.

Artinya: **bug parser indexer**, bukan kerusakan PLX. Workaround akan dikerjakan TonAPI.

| Bukti | Nilai |
|-------|-------|
| Jetton kedua terdampak | `EQBwLccXri43Tm5MetSghCB6bKaO2AygLZtXZgoN3x5UOQqW` → `/v2/jettons/` juga **404** |
| PLX `minter.ton.org` | `Unable to execute get method. Got exit_code: -13` (gejala sama) |
| PLX `/v2/rates` | `USD: 0` — fiat mati selama katalog hilang |
| DexScreener | `pairs: null` |

Tidak ada aksi on-chain yang bisa memperbaiki PLX genesis (admin sudah null, tanpa kunci admin).
Yang tersisa: tunggu workaround TonAPI, lalu verifikasi `/v2/jettons/` = **200** dan `verification: whitelist`.

## RESOLVED — katalog pulih (2026-08-28 ~16:30 WIB)

TonAPI Tech balas **"Gonna reindex"**, lalu `GET /v2/jettons/EQCba…` kembali **200**.

| Field | Nilai |
|-------|-------|
| `verification` | **whitelist** |
| `name` / `symbol` | Phalanx / **PLX** |
| `total_supply` | 1e18 (1B @ 9 desimal) |
| `mintable` | `false` |
| `holders_count` | 9 |
| `interfaces` | `jetton_master` |
| image + preview | cache TonAPI imgproxy OK |

Masih **belum** pulih (gate terpisah, bukan bug indexer):

| Item | Status | Syarat |
|------|--------|--------|
| `/v2/rates` USD | `0` | LP ≥ ~100 TON + holders ≥ 100 |
| DexScreener | `pairs: null` | butuh aktivitas swap pada pool |

## History

- Issue publik `tonkeeper/opentonapi#963` — jangan revive dari akun pribadi; eskalasi lewat `@tonapi_bot`.
- 2026-08-28 — TonAPI Tech konfirmasi root cause null-admin + rencana workaround.
- 2026-08-28 — reindex dijalankan TonAPI; katalog **200**, `verification: whitelist`. Selesai.
