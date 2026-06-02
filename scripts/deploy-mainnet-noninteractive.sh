#!/usr/bin/env bash
# Non-interactive PLX mainnet deploy (distribution + splitter).
# Run on Ubuntu server: ~/projects/plx-acton with acton + wallets.toml.
#
# Prerequisites:
#   - plx-deployer-v2 funded with >= 5 TON on mainnet
#   - PLX_VESTING_START set (unix timestamp, e.g. date +%s)
#
# Usage:
#   export PLX_VESTING_START=$(date +%s)
#   ./scripts/deploy-mainnet-noninteractive.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTON="${ACTON:-$HOME/.acton/bin/acton}"

: "${PLX_VESTING_START:?Set PLX_VESTING_START (unix timestamp)}"

export PLX_DEPLOYER="${PLX_DEPLOYER:-plx-deployer-v2}"
# Mainnet distribution wallets (EQ). Override via env if rotating wallets.
export PLX_TREASURY="${PLX_TREASURY:-EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX}"
export PLX_LP="${PLX_LP:-EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH}"
export PLX_COMMUNITY="${PLX_COMMUNITY:-EQD1XDv0Awjx0GUVv6YQYYnvEmjcKJ9iEBjvtHPM2nWML-q9}"
export PLX_MARKETING="${PLX_MARKETING:-EQDB9yVhkPvEhMFo90fqHWzqYj2mESAlwObMbA6LX7fETtN6}"
export PLX_BENEFICIARY="${PLX_BENEFICIARY:-EQB5_ndfsF6gSuMDYYA4Uq2R26jPRzEsvFK-glI9VwbzLdYH}"

LOG="${ROOT}/.deploy-mainnet.log"
exec > >(tee -a "$LOG") 2>&1

echo "==> $(date -Is) PLX mainnet deploy starting"
echo "==> Pre-flight: test + build"
"$ACTON" test
"$ACTON" build

echo "==> Step 1/2: deploy-distribution (minter + vesting + mint 1B PLX)"
"$ACTON" script scripts/deploy-distribution.tolk --net mainnet

# Parse minter from log tail (script prints PLX_MINTER_ADDRESS=...)
MINTER=$(grep -oP 'PLX_MINTER_ADDRESS=\K[^ ]+' "$LOG" | tail -1)
if [[ -z "$MINTER" ]]; then
  echo "ERROR: could not parse PLX_MINTER_ADDRESS from log"
  exit 1
fi

export JETTON_MINTER_ADDRESS="$MINTER"
export TREASURY_ADDRESS="$PLX_TREASURY"
export SPLITTER_DEPLOYER="$PLX_DEPLOYER"

echo "==> Step 2/2: deploy-splitter (PaymentSplitter 50/50 burn/treasury)"
"$ACTON" script scripts/deploy-splitter.tolk --net mainnet

echo ""
echo "==> Mainnet deploy complete. Save addresses from log:"
echo "    Log file: $LOG"
echo "    Minter:   $MINTER"
echo "    Next: acton verify JettonMinter --net mainnet (and Wallet, TeamVesting, PaymentSplitter)"
