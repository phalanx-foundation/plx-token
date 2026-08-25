#!/usr/bin/env bash
# Verify Tonkeeper ton-assets whitelist status for PLX mainnet minter.
set -euo pipefail
MINTER="${PLX_JETTON_MINTER_MAINNET:-EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS}"
PR="${TON_ASSETS_PR:-5540}"

echo "=== TonAPI verification ==="
curl -sS "https://tonapi.io/v2/jettons/${MINTER}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('verification:', d.get('verification'))
print('is_scam:', (d.get('admin') or {}).get('is_scam'))
print('holders:', d.get('holders_count'))
"

echo ""
echo "=== ton-assets PR #${PR} ==="
if command -v gh >/dev/null 2>&1; then
  gh pr view "$PR" --repo tonkeeper/ton-assets --json state,mergeable,url 2>/dev/null || true
else
  echo "gh CLI not installed — open https://github.com/tonkeeper/ton-assets/pull/${PR}"
fi

echo ""
echo "Success = verification: whitelist (after maintainer merge + 15-60 min cache)"
