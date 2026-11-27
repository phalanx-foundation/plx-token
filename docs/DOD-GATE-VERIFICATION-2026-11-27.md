# DoD Gate Verification — 27 Nov 2026 (re-verify "blocked" report)

Laporan dashboard: gerbang `noErrors` berstatus **blocked** dengan alasan
"workspace tidak ditemukan". Verifikasi ulang langsung menunjukkan laporan
tersebut adalah **false positive**.

## Lingkungan verifikasi
- Shell: non-login, `env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/home/dev`
  (replika kondisi runner yang tidak punya PATH toolchain).
- Command: `npm run gate`
- Repo: /home/dev/plx-token → remote origin
  https://github.com/phalanx-foundation/plx-token, branch `master`.

## Hasil (live, 27 Nov 2026 ± 07:45 WIB / 00:45 UTC)
| Step | Hasil |
|---|---|
| Workspace exists | ✅ `/home/dev/plx-token`, remote `phalanx-foundation/plx-token`, branch master |
| `npm run gate` (build + fmt --check + check + test) | ✅ **EXIT=0** |
| Test suite | ✅ 185 passed in 21 files |
| `acton check` | ✅ exit 0, hanya warning non-blocking (E028/E016/E019/S005) |

## Analisis akar "blocked (workspace tidak ditemukan)"
- Path workspace yang valid dan kanonik: **/home/dev/plx-token**.
- Scanner/agent yang tidak tahu path kanonik ini akan salah menyimpulkan
  "workspace tidak ditemukan". Empat clone lain yang ditemukan pada 24 Nov
  (workspace/, work/, workspaces/, PLX-ACTON) bukan workspace kanonik.
- Per 24 Nov, `.dod.json` juga mencatat laporan "blocked (workspace tidak
  ditemukan)" sebagai false positive; `note` pada gate `noErrors` di
  `.dod.json` menegaskan workspace kanonik ADA dan gate bisa diselesaikan
  dari non-login shell.

## Catatan toolchain (sudah diatasi sebelumnya)
- `scripts/acton-run.sh` meng-wrap semua call `acton` dan self-resolve
  `$HOME/.acton/bin/acton` sehingga tidak bergantung pada PATH shell.
  Ini sudah di-commit (commit `faf64cf fix(dod): make noErrors gate
  resolvable from non-login shell`) dan terbukti efektif: `env -i ... npm
  run gate` → EXIT=0.
- Versi Acton yang dipakai sesuai pin `[toolchain].acton` di `Acton.toml`.

## Bukti
- `.dod.json` → `gates.noErrors`: `status=pass`, `lastRun=2026-11-27T01:41:47Z`,
  detail "acton check exit 0; hanya warning non-blocking E028/E016/E019/S005".
- `npm run gate` dijalankan ulang di turn ini, EXIT=0, 185/185 tests passed.

## Kesimpulan
Gerbang `noErrors` **bukan** blocked — laporan "workspace tidak ditemukan"
merupakan false positive. Workspace kanonik `/home/dev/plx-token` ada,
akses ke repo `phalanx-foundation/plx-token` tersedia, build+fmt+check+test
jalan bersih, 185/185 test lulus.
