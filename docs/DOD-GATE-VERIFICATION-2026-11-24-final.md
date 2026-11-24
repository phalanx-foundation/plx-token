# DoD Gate Verification — PLX Token (TON Jetton) — 2026-11-24 (WIB)

Status: **SEMUA GERBANG PASS** · Workspace: `/home/dev/plx-token` · Head: `7ceab0e`

## Ringkasan gerbang

| Gerbang | Status | Bukti |
|---|---|---|
| workspace | PASS | Dir ada, remote `phalanx-foundation/plx-token`, head `7ceab0e` |
| noErrors | PASS | `npm run gate` → EXIT=0 di shell bersih |
| build | PASS | `acton build` 2-pass exit 0; hanya warning non-blocking E028/E016 |
| test | PASS | 185 passed in 21 files, exit 0 |
| fmt | PASS | `acton fmt --check` exit 0 |

## Perintah verifikasi (shell bersih, non-login — sama seperti runner CI)

```
cd /home/dev/plx-token
env -i HOME=/home/dev PATH=/usr/local/bin:/usr/bin:/bin bash -c 'npm run gate'
# EXIT=0
```

`npm run gate` = `build && fmt --check && check && test` melalui `scripts/acton-run.sh`,
yang me-resolve `~/.acton/bin/acton` (versi 1.1.0, cocok dengan pin `[toolchain].acton` di `Acton.toml`).

## Catatan koreksi klaim "blocked"

1. **"workspace tidak ditemukan"** — false positive. Workspace kanonik ada di `/home/dev/plx-token`
   (remote cocok). Scanner tidak mengetahui path kanonik. Empat clone lain juga ada; kanonik sudah ditetapkan.
2. **"perkakas `./scripts/acton-run.sh` tidak terpasang"** — sudah tidak benar. Berkas ada, executable,
   dan gate berjalan nyata melaluinya.
3. Runner test proyek ini **Acton/Tolk**, bukan pytest. 185 test tersebar di 21 berkas `tests/*.test.tolk`.

## Metadata TEP-74

- `metadata/phalanx-metadata.json` — `name`, `symbol=PLX`, `decimals=9`, `image` (valid)
- `metadata/logo-512.png` — PNG 512x512, 8-bit/color RGBA
- `metadata/plx-logo-ipfs.json` — valid, `cid` masih kosong (non-blocking; menunggu pin IPFS)

## CI

`.github/workflows/contracts.yml` — `on: push/pull_request branches [master]` + `workflow_dispatch`.
Step: checkout → baca pin Acton dari `Acton.toml` → cache/install Acton → verifikasi versi →
`acton init` → build pass-1 (toleran) → build pass-2 (gate) → `acton check` → `acton fmt --check` (blocking) → `acton test`.
