#!/usr/bin/env bash
set -euo pipefail

# verify-contract.sh — publish contract source code to TON Verifier
# Called by acton-worker /verify endpoint
#
# Required env: CONTRACT, NETWORK, MINTER_ADDRESS, DEPLOYMENT_ID
# Outputs JSON: {"contract":"JettonMinter","network":"mainnet","minter_address":"EQ...","deployment_id":"uuid","output":"..."}

CONTRACT="${CONTRACT:-}"
NETWORK="${NETWORK:-}"
MINTER_ADDRESS="${MINTER_ADDRESS:-}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-}"

if [ -z "$CONTRACT" ] || [ -z "$NETWORK" ] || [ -z "$MINTER_ADDRESS" ]; then
    echo '{"error":"Missing required env: CONTRACT, NETWORK, or MINTER_ADDRESS"}'
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PLX_ROOT"

echo "{}" >&2
echo "verify-contract: contract=$CONTRACT network=$NETWORK address=$MINTER_ADDRESS" >&2

# Run acton verify
# A failed publish must exit non-zero: exiting 0 made the caller record
# "Source Code Verified" for contracts that were never published.
OUTPUT=$(acton verify "$CONTRACT" --net "$NETWORK" --address "$MINTER_ADDRESS" 2>&1) || {
    echo "{\"contract\":\"$CONTRACT\",\"network\":\"$NETWORK\",\"minter_address\":\"$MINTER_ADDRESS\",\"deployment_id\":\"$DEPLOYMENT_ID\",\"verified\":false,\"error\":\"$(echo "$OUTPUT" | head -1 | sed 's/"/\\"/g')\",\"output\":\"$(echo "$OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')\"}"
    exit 1
}

echo "{\"contract\":\"$CONTRACT\",\"network\":\"$NETWORK\",\"minter_address\":\"$MINTER_ADDRESS\",\"deployment_id\":\"$DEPLOYMENT_ID\",\"verified\":true,\"output\":\"$(echo "$OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')\"}"