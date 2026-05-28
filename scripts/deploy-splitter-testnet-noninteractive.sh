#!/usr/bin/env bash
# Non-interactive PaymentSplitter testnet deploy for Ubuntu server.
# Usage (on server with acton + repo cloned):
#   export JETTON_MINTER_ADDRESS=kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV
#   export TREASURY_ADDRESS=kQCAfIuFFlS8RJyYQU7pFaN1XqcO8V4lZl-SH8Ca950XqGal
#   export SPLITTER_DEPLOYER=phalanx-deployer
#   ./scripts/deploy-splitter-testnet-noninteractive.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${JETTON_MINTER_ADDRESS:?Set JETTON_MINTER_ADDRESS}"
: "${TREASURY_ADDRESS:?Set TREASURY_ADDRESS}"
: "${SPLITTER_DEPLOYER:?Set SPLITTER_DEPLOYER wallet name in acton secrets}"

echo "==> Building contracts"
acton build

echo "==> Running splitter tests"
acton test tests/splitter.test.tolk

echo "==> Deploying PaymentSplitter to testnet"
acton run deploy-splitter-testnet

echo ""
echo "Copy SPLITTER_ADDRESS above into Cloudflare Pages:"
echo "  NEXT_PUBLIC_PLX_SPLITTER_TESTNET=<address>"
