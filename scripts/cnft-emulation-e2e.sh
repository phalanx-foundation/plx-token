#!/usr/bin/env bash
# Emulation: merkle build + deploy + claim in one Acton process
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ACTON="${ACTON:-$HOME/.acton/bin/acton}"
PYTHON="${PYTHON:-python3}"
export PATH="$(dirname "$ACTON"):$PATH"

OWNER="${NFT_OWNER_ADDRESS:-EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c}"
COUNT="${NFT_ITEM_COUNT:-2}"
export NFT_OWNER_ADDRESS="$OWNER"
export COLLECTION_NAME="${COLLECTION_NAME:-CnftE2E}"
export COLLECTION_DESCRIPTION="${COLLECTION_DESCRIPTION:-e2e}"
export COLLECTION_IMAGE_URL="${COLLECTION_IMAGE_URL:-https://example.com/c.png}"
export ROYALTY_FACTOR="${ROYALTY_FACTOR:-500}"
export ROYALTY_BASE="${ROYALTY_BASE:-10000}"
export JETTON_DEPLOYER="${JETTON_DEPLOYER:-toolkit-deployer-testnet}"
export NFT_ITEM_INDEX="${NFT_ITEM_INDEX:-0}"
export NFT_ITEM_NAME="${NFT_ITEM_NAME:-Claim0}"
export NFT_ITEM_DESCRIPTION="${NFT_ITEM_DESCRIPTION:-d}"
export NFT_ITEM_IMAGE_URL="${NFT_ITEM_IMAGE_URL:-https://example.com/0.png}"

MERKLE_TMP="$(mktemp)"
trap 'rm -f "$MERKLE_TMP"' EXIT
"$PYTHON" scripts/cnft_merkle.py --owner "$OWNER" --count "$COUNT" --out "$MERKLE_TMP" >/dev/null
export CNFT_MERKLE_ROOT
CNFT_MERKLE_ROOT="$("$PYTHON" -c "import json; print(json.load(open(r'$MERKLE_TMP'))['merkle_root'])")"
export CNFT_MAX_SUPPLY
CNFT_MAX_SUPPLY="$("$PYTHON" -c "import json; print(json.load(open(r'$MERKLE_TMP'))['max_supply'])")"

IDX="${NFT_ITEM_INDEX}"
"$PYTHON" -c "
import json
p=json.load(open(r'$MERKLE_TMP'))
sibs=p['proofs']['$IDX']['siblings_dec']
open('/tmp/cnft-proof-env.sh','w').write(''.join(f'export CNFT_PROOF_{i}={s}\n' for i,s in enumerate(sibs)))
"
# shellcheck disable=SC1091
source /tmp/cnft-proof-env.sh

"$ACTON" build NftItem >&2
"$ACTON" build CompressedNftCollection >&2
"$ACTON" script scripts/cnft-deploy-claim.tolk
