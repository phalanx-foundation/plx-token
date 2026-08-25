#!/usr/bin/env bash
# Deploy FeeJettonWallet + FeeJettonMinter
# Usage: bash scripts/deploy-fee-jetton.sh [--net testnet|mainnet]
set -euo pipefail

NET="${1:-}"
ACTON_ARGS=""
if [[ "$NET" == "--net" && -n "${2:-}" ]]; then
    ACTON_ARGS="--net $2"
fi

echo "==> Building contracts..."
acton build

echo "==> Running FeeJetton deploy script..."
acton script scripts/deploy-fee-jetton.tolk $ACTON_ARGS

echo "==> Done."
