# Drop Admin — client safety verification (2026-08-28)

## Verdict

| Layer | Status | Evidence |
|-------|--------|----------|
| Kontrak `DropMinterAdmin` | **PASS (template baru)** | Set `burnAdminAddress()` = wc0+zero hash, bukan null |
| `get_jetton_data` | **PASS (template baru)** | Selalu MsgAddressInt; `mintable=false` jika burn |
| Acton tests | **PASS** | `tests/admin-and-governance.test.tolk` — drop → burn, mint gagal |
| Dashboard payload | **PASS** | `0x7431f221` + queryId; copy burn address docs.ton.org |
| Gate UI | **PASS** | Hide tools jika admin null/burn; PLX genesis sudah revoked |
| PLX genesis on-chain | **LEGACY** | Admin masih empty list (drop lama); tidak bisa upgrade |

## Client risk

Token yang di-deploy **dengan bytecode lama** (null-drop) masih berbahaya jika Drop Admin diklik.  
Token yang di-deploy **setelah** `acton build` post-fix burn-path → aman (indexer-compatible).

Mitigasi: acton-worker di Ubuntu sudah `git pull` + `acton build` (2026-08-28). Deploy client baru memakai kode burn-path.

## Jangan

- Drop Admin pada minter yang masih bytecode null-drop tanpa upgrade code dulu
- Klaim “aman” tanpa tes Acton di atas hijau
