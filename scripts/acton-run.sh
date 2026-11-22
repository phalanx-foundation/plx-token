#!/usr/bin/env bash
# Thin launcher for the pinned Acton toolchain.
#
# Why this exists: the DoD/CI runners invoke `npm run build|test|lint` through a
# non-login shell, so ~/.acton/bin is not on PATH and acton would be reported as
# "blocked" (missing toolchain) instead of actually compiling the contracts.
# This wrapper resolves the binary itself and refuses to run on a version
# mismatch with [toolchain].acton, which is what the real CI job enforces too.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

acton_bin="${ACTON_BIN:-}"
if [ -z "$acton_bin" ]; then
  for cand in "$HOME/.acton/bin/acton" "$(command -v acton 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then acton_bin="$cand"; break; fi
  done
fi
if [ -z "$acton_bin" ] || [ ! -x "$acton_bin" ]; then
  echo "acton: CLI tidak ditemukan (install dari Acton.toml [toolchain].acton)" >&2
  exit 127
fi

# Versi wajib sama dengan pin proyek; aktif acton menolak jalan kalau berbeda,
# tapi kita gagalkan lebih awal dengan pesan yang jelas.
want="$(grep -m1 '^acton = ' Acton.toml | cut -d'"' -f2 || true)"
if [ -n "$want" ]; then
  have="$("$acton_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ "$have" != "$want" ]; then
    echo "acton: versi tidak cocok (butuh $want, terpasang ${have:-unknown})" >&2
    exit 1
  fi
fi

exec "$acton_bin" "$@"
