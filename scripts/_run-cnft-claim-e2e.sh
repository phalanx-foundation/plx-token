#!/usr/bin/env bash
set -euo pipefail
export PATH=/home/dev/.acton/bin:$PATH
cd ~/projects/plx-acton
COLL=$(python3 -c 'import json; print(json.load(open("/tmp/cnft-e2e.out"))["collection_address"])')
PROOFS=$(python3 -c 'import json; print(json.load(open("/tmp/cnft-e2e.out"))["proofs_file"])')
echo "COLL=$COLL"
python3 -c "
import json
p=json.load(open('$PROOFS'))
sibs=p['proofs']['0']['siblings_dec']
open('/tmp/cnft-proof-env.sh','w').write(''.join(f'export CNFT_PROOF_{i}={s}\n' for i,s in enumerate(sibs)))
print('proofs', len(sibs))
"
# shellcheck disable=SC1091
source /tmp/cnft-proof-env.sh
export NFT_COLLECTION_ADDRESS="$COLL"
export NFT_OWNER_ADDRESS=EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c
export NFT_ITEM_OWNER="$NFT_OWNER_ADDRESS"
export NFT_ITEM_INDEX=0
export NFT_ITEM_NAME=Claim0
export NFT_ITEM_DESCRIPTION=d
export NFT_ITEM_IMAGE_URL=https://example.com/0.png
export JETTON_DEPLOYER=toolkit-deployer-testnet
acton script scripts/claim-cnft-item.tolk 2>&1 | tee /tmp/cnft-claim.out | tail -60
