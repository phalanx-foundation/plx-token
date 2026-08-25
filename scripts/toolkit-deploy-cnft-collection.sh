#!/usr/bin/env bash
# Deploy Compressed NFT Collection (TEP #126) via acton on Ubuntu
# Called by acton-worker POST /deploy-nft
set -euo pipefail

PLX_ACTON_ROOT="${PLX_ACTON_ROOT:-/home/dev/projects/plx-acton}"
NETWORK="${network:-testnet}"
COLLECTION_NAME="${COLLECTION_NAME:-Unnamed Collection}"
COLLECTION_DESCRIPTION="${COLLECTION_DESCRIPTION:-}"
COLLECTION_IMAGE_URL="${COLLECTION_IMAGE_URL:-}"
NFT_OWNER_ADDRESS="${NFT_OWNER_ADDRESS:-}"
NFT_ITEM_COUNT="${NFT_ITEM_COUNT:-0}"
ROYALTY_PERCENT="${ROYALTY_PERCENT:-0}"
NFT_ITEMS_JSON="${NFT_ITEMS_JSON:-[]}"

OWNER="$NFT_OWNER_ADDRESS"
COUNT="$NFT_ITEM_COUNT"
ROYALTY_FACTOR=$(awk "BEGIN {printf \"%d\", $ROYALTY_PERCENT * 100}")
ROYALTY_BASE=10000
ROYALTY_ADDR="$OWNER"

cd "$PLX_ACTON_ROOT"

# Step 1: Build contracts
echo "[cnft-deploy] Building contracts..." >&2
# Acton 1.1 accepts a single CONTRACT_NAME (or all if omitted)
acton build NftItem 2>&1
acton build CompressedNftCollection 2>&1

# Step 2: Read NftItem code
NFT_ITEM_CODE_CELL=$(cat build/NftItem.compiled.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null || echo "")

# Step 3: Generate Merkle tree from items
echo "[cnft-deploy] Generating Merkle tree for $COUNT items..." >&2

MERKLE_DATA=$(python3 -c "
import json, hashlib, sys, math

def hash_pair(a, b):
    return hashlib.sha256((a + b).encode('utf-8')).hexdigest()

def hash_leaf(index, owner):
    data = f'{index}:{owner}'
    return hashlib.sha256(data.encode('utf-8')).hexdigest()

items = json.loads('$NFT_ITEMS_JSON')
n = $COUNT
depth = 8  # support up to 256 items

# Build leaves
leaves = []
for i in range(2**depth):
    if i < n:
        leaves.append(hash_leaf(i, '$OWNER'))
    else:
        leaves.append('0' * 64)  # zero hash for empty

# Build tree bottom-up
tree = [leaves]
for level in range(depth):
    parent = []
    for i in range(0, len(tree[-1]), 2):
        parent.append(hash_pair(tree[-1][i], tree[-1][i+1]))
    tree.append(parent)

merkle_root = tree[-1][0]

# Generate proofs per item
proofs = {}
for item_idx in range(n):
    proof_siblings = []
    idx = item_idx
    for level in range(depth):
        sibling_idx = idx ^ 1  # flip last bit
        proof_siblings.append(tree[level][sibling_idx])
        idx //= 2
    proofs[str(item_idx)] = proof_siblings

result = {
    'merkle_root': merkle_root,
    'max_supply': 2**depth,
    'tree_depth': depth,
    'proofs': proofs
}
print(json.dumps(result))
" 2>&1)

MERKLE_ROOT=$(echo "$MERKLE_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['merkle_root'])" 2>/dev/null || echo "")
MAX_SUPPLY=$(echo "$MERKLE_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['max_supply'])" 2>/dev/null || echo "256")

echo "[cnft-deploy] Merkle root: $MERKLE_ROOT" >&2

# Step 4: Deploy CompressedNftCollection
COLLECTION_CONTENT=$(python3 -c "
import json
content = {
    'name': '$COLLECTION_NAME',
    'description': '$COLLECTION_DESCRIPTION',
    'image': '$COLLECTION_IMAGE_URL',
    'cover_image': '$COLLECTION_IMAGE_URL',
}
print(json.dumps(content))
")

echo "[cnft-deploy] Deploying CompressedNftCollection on $NETWORK..." >&2

DEPLOY_OUTPUT=$(acton run deploy-cnft-collection \
    --network "$NETWORK" \
    --owner "$OWNER" \
    --name "$COLLECTION_NAME" \
    --content "$COLLECTION_CONTENT" \
    --item-code "$NFT_ITEM_CODE_CELL" \
    --merkle-root "$MERKLE_ROOT" \
    --max-supply "$MAX_SUPPLY" \
    --royalty-factor "$ROYALTY_FACTOR" \
    --royalty-base "$ROYALTY_BASE" \
    --royalty-address "$ROYALTY_ADDR" \
    2>&1)

COLLECTION_ADDRESS=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; d=json.loads(next(l for l in sys.stdin if l.strip())); print(d.get('collection_address',''))" 2>/dev/null || echo "")
DEPLOY_TX=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; d=json.loads(next(l for l in sys.stdin if l.strip())); print(d.get('tx_hash',''))" 2>/dev/null || echo "")

if [ -z "$COLLECTION_ADDRESS" ]; then
    echo '{"error": "Failed to deploy CompressedNftCollection", "output": "'"$(echo "$DEPLOY_OUTPUT" | head -5 | tr '\n' ' ')"'"}' >&2
    exit 1
fi

# Step 5: Save proofs for claim API
PROOFS_FILE="$PLX_ACTON_ROOT/data/cnft-proofs-${COLLECTION_ADDRESS}.json"
echo "$MERKLE_DATA" > "$PROOFS_FILE"
echo "[cnft-deploy] Proofs saved to $PROOFS_FILE" >&2

# Step 6: Output JSON
echo "{\"collection_address\": \"$COLLECTION_ADDRESS\", \"deploy_tx_hash\": \"$DEPLOY_TX\", \"merkle_root\": \"$MERKLE_ROOT\", \"max_supply\": $MAX_SUPPLY, \"mode\": \"cnft_broadcast\", \"proofs_file\": \"$PROOFS_FILE\"}"
