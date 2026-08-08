#!/usr/bin/env bash
# Deploy NFT Collection (TEP-62) via acton on Ubuntu
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

# royalty: percent -> (factor, base)
# e.g. 5% -> factor=500, base=10000
ROYALTY_FACTOR=$(awk "BEGIN {printf \"%d\", $ROYALTY_PERCENT * 100}")
ROYALTY_BASE=10000
ROYALTY_ADDR="$OWNER"

cd "$PLX_ACTON_ROOT"

# Step 1: Build
echo "[nft-deploy] Building contracts..." >&2
acton build NftCollection NftItem 2>&1

# Step 2: Query NftItem code hash and code cell
echo "[nft-deploy] Reading NftItem code..." >&2
NFT_ITEM_CODE_CELL=$(acton code-cell NftItem 2>/dev/null || echo "")
if [ -z "$NFT_ITEM_CODE_CELL" ]; then
    # Fallback: get compiled boc
    NFT_ITEM_CODE_CELL=$(cat build/NftItem.compiled.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null || echo "")
fi

# Step 3: Deploy NftCollection with initial data
echo "[nft-deploy] Deploying NftCollection on $NETWORK..." >&2

COLLECTION_CONTENT=$(python3 -c "
import json
content = {
    'name': '$COLLECTION_NAME',
    'description': '$COLLECTION_DESCRIPTION',
    'image': '$COLLECTION_IMAGE_URL',
    'cover_image': '$COLLECTION_IMAGE_URL',
    'external_url': '',
    'social_links': []
}
print(json.dumps(content))
")

DEPLOY_OUTPUT=$(acton run deploy-nft-collection \
    --network "$NETWORK" \
    --owner "$OWNER" \
    --name "$COLLECTION_NAME" \
    --content "$COLLECTION_CONTENT" \
    --item-code "$NFT_ITEM_CODE_CELL" \
    --royalty-factor "$ROYALTY_FACTOR" \
    --royalty-base "$ROYALTY_BASE" \
    --royalty-address "$ROYALTY_ADDR" \
    2>&1)

COLLECTION_ADDRESS=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; d=json.loads(next(l for l in sys.stdin if l.strip())); print(d.get('collection_address',''))" 2>/dev/null || echo "")
DEPLOY_TX=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; d=json.loads(next(l for l in sys.stdin if l.strip())); print(d.get('tx_hash',''))" 2>/dev/null || echo "")

if [ -z "$COLLECTION_ADDRESS" ]; then
    echo '{"error": "Failed to deploy NftCollection", "output": "'"$(echo "$DEPLOY_OUTPUT" | head -5 | tr '\n' ' ')"'"}' >&2
    exit 1
fi

echo "[nft-deploy] Collection deployed: $COLLECTION_ADDRESS" >&2

# Step 4: Mint individual NFT items
ITEM_ADDRESSES="["
for i in $(seq 0 $((COUNT - 1))); do
    ITEM_NAME=$(echo "$NFT_ITEMS_JSON" | python3 -c "
import sys,json
items=json.load(sys.stdin)
if $i < len(items):
    print(items[$i].get('name','Item $i'))
else:
    print('Item $i')
" 2>/dev/null || echo "Item $i")

    ITEM_DESC=$(echo "$NFT_ITEMS_JSON" | python3 -c "
import sys,json
items=json.load(sys.stdin)
if $i < len(items):
    print(items[$i].get('description',''))
else:
    print('')
" 2>/dev/null || echo "")

    ITEM_IMAGE=$(echo "$NFT_ITEMS_JSON" | python3 -c "
import sys,json
items=json.load(sys.stdin)
if $i < len(items):
    print(items[$i].get('imageUrl',''))
else:
    print('')
" 2>/dev/null || echo "")

    ITEM_CONTENT=$(python3 -c "
import json
content = {
    'name': '$ITEM_NAME',
    'description': '$ITEM_DESC',
    'image': '$ITEM_IMAGE'
}
print(json.dumps(content))
")

    echo "[nft-deploy] Minting item $i: $ITEM_NAME" >&2

    MINT_OUTPUT=$(acton run mint-nft-item \
        --network "$NETWORK" \
        --collection "$COLLECTION_ADDRESS" \
        --index "$i" \
        --owner "$OWNER" \
        --content "$ITEM_CONTENT" \
        2>&1)

    ITEM_ADDR=$(echo "$MINT_OUTPUT" | python3 -c "import sys,json; d=json.loads(next(l for l in sys.stdin if l.strip())); print(d.get('item_address',''))" 2>/dev/null || echo "")

    if [ -n "$ITEM_ADDR" ]; then
        if [ "$i" -gt 0 ]; then
            ITEM_ADDRESSES="$ITEM_ADDRESSES,"
        fi
        ITEM_ADDRESSES="$ITEM_ADDRESSES\"$ITEM_ADDR\""
    fi
done
ITEM_ADDRESSES="$ITEM_ADDRESSES]"

# Step 5: Output JSON result
echo "{\"collection_address\": \"$COLLECTION_ADDRESS\", \"deploy_tx_hash\": \"$DEPLOY_TX\", \"item_addresses\": $ITEM_ADDRESSES, \"mode\": \"nft_broadcast\"}"
