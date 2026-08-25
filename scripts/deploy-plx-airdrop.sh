#!/usr/bin/env bash
# Deploy PlxAirdrop contract
# Usage: bash scripts/deploy-plx-airdrop.sh [--net testnet|mainnet]
set -euo pipefail

NET="${1:-}"
ACTON_ARGS=""
if [[ "$NET" == "--net" && -n "${2:-}" ]]; then
    ACTON_ARGS="--net $2"
fi

echo "==> Building contracts..."
acton build

echo "==> Running PlxAirdrop deploy script..."
acton script scripts/deploy-airdrop.tolk $ACTON_ARGS

echo "==> Done."
