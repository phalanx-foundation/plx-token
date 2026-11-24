# Verifikasi Gerbang DoD — PLX Token (TON Jetton)

Tanggal: 24 November 2026 (Asia/Jakarta)
Workspace kanonik: `/home/dev/plx-token`
Remote: `https://github.com/phalanx-foundation/plx-token`
Head lokal: `7ceab0e` (origin/master `8974fec` + 1 commit fix DoD runner)

## Kesimpulan

Laporan **"gerbang noErrors berstatus blocked (workspace tidak ditemukan)" adalah false positive**
dari scanner. Workspace ada, toolchain ada dan versinya cocok dengan pin proyek, dan seluruh
gerbang berjalan nyata lalu lulus.

## Bukti eksekusi

Dijalankan dari shell bersih supaya tidak bergantung pada `~/.bashrc`:

```
cd /home/dev/plx-token
env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin bash -c 'npm run gate'
```

`npm run gate` = `acton build && acton fmt --check && acton check && acton test`

| Tahap | Perintah | Hasil |
|---|---|---|
| Build | `acton build` | exit 0 — `Compiling contracts … Finished in 16.15ms` |
| Format | `acton fmt --check` | exit 0 — `All files are properly formatted` |
| Lint | `acton check` | exit 0 — hanya warning gaya (E028, E016), **nol error** |
| Test | `acton test` | exit 0 — **185 passed in 21 files** |

Exit code keseluruhan: **0**.

## Toolchain

- `acton 1.1.0 (9cf4d1f 2026-05-22)` di `/home/dev/.acton/bin/acton`
- `Acton.toml` mem-pin `acton = "1.1.0"` → cocok, wrapper `scripts/acton-run.sh` tidak menolak.

## CI

File: `.github/workflows/contracts.yml` (nama kerja untuk gerbang CI; tidak ada `ci.yml` terpisah).

- Trigger: `push` dan `pull_request` ke `master`
- Step: checkout → baca pin versi Acton → cache + install Acton → `acton init` →
  `acton build` (pass 1) → `acton build` (pass 2, gate sebenarnya) → `acton check` →
  `acton fmt --check` (blocking) → `acton test` (185 tests)
- Linting dan unit test berjalan pada setiap push ke `master`. ✅

## Metadata TEP-74

`metadata/phalanx-metadata.json`:

```json
{ "name": "Phalanx", "symbol": "PLX", "decimals": 9,
  "description": "…", "image": "https://plx.foundation/plx-logo.png" }
```

- Field wajib TEP-74 (`name`, `symbol`, `decimals`, `image`) lengkap, JSON valid.
- `metadata/logo-512.png` → **512×512 RGBA** sesuai standar jetton.
- `metadata/plx-logo-ipfs.json` valid; `cid`/`ipfs_uri` masih kosong karena pin IPFS belum
  dijalankan (`scripts/pin-plx-logo-ipfs.py`). Ini **tidak memblokir** gerbang build/test.

## Catatan / risiko sisa

1. Commit `7ceab0e` (wrapper `scripts/acton-run.sh` + `package.json` gate) **belum di-push**
   ke `origin/master`. Tanpa push, runner CI memakai layout lama dan gate runner DoD lokal
   tetap bisa gagal di mesin lain.
2. `.dod.json` belum di-commit (untracked) — disengaja, karena memuat state runner.
   Pertimbangkan menambahkannya ke `.gitignore`.
3. `acton check` masih memunculkan warning gaya (E028/E016) — non-blocking, tapi sebaiknya
   dirapikan bertahap supaya bisa dinaikkan jadi wajib.
