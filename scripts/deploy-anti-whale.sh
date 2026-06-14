#!/usr/bin/env bash
# Deploy AntiWhaleJettonWallet (paired with JettonMinter)
# Usage: bash scripts/deploy-anti-whale.sh [--net testnet|mainnet]
set -euo pipefail

NET="${1:-}"
ACTON_ARGS=""
if [[ "$NET" == "--net" && -n "${2:-}" ]]; then
    ACTON_ARGS="--net $2"
fi

echo "==> Building contracts..."
acton build

echo "==> Running AntiWhale deploy script..."
acton script scripts/deploy-anti-whale.tolk $ACTON_ARGS

echo "==> Done."
