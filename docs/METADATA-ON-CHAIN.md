# On-chain jetton metadata (logo / icon)

PLX and every jetton deployed through Phalanx store **name, symbol, decimals, description, and image** in the minter's **on-chain metadata cell** (TEP-64 dictionary). Wallets and explorers (Tonviewer, Tonkeeper, TonAPI) read that cell — not your website form or local `metadata/` folder.

## IPFS storage (Pinata + Cloudflare Gateway)

Client token logos uploaded via the toolkit wizard are **pinned to IPFS with Pinata** and served through the **Cloudflare IPFS Gateway** at `https://ipfs.plx.foundation/ipfs/{CID}`.

| Layer | Role |
|-------|------|
| **Pinata** | Upload / pin (write) |
| **Cloudflare IPFS Gateway** | HTTP serve (read) |
| **On-chain `image`** | Prefer `ipfs://{CID}` for decentralization |
| **Dashboard / API** | Resolve `ipfs://` → gateway HTTPS URL |

Setup: [`IPFS-SETUP.md`](IPFS-SETUP.md)

Pin PLX native logo once:

```powershell
powershell -File ".scripts/ops/load-env.ps1"
python scripts/pin-plx-logo-ipfs.py
```

## Why the testnet icon did not change

Changing any of these **does not** update what Tonviewer shows:

- Uploading a logo in the **toolkit build wizard** (that only affects *your* draft deployment until deploy + on-chain update).
- Editing `metadata/logo.png` locally without an on-chain transaction.
- Replacing the file on GitHub **without** sending `ChangeMinterMetadata` (explorers may also cache the old image URL for hours).

The live PLX testnet minter (`kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV`) still points to whatever `image` key was set at deploy or last metadata update.

TonAPI caches previews — even after you update on-chain, allow **15–60 minutes** or use a **new CID/URL** to bust caches.

## How to update PLX testnet metadata (operator)

**Requirements:** Acton CLI, testnet minter **admin** wallet (`plx-deployer-v2`), ~0.05 TON for gas.

### Option A — refresh script (recommended)

```powershell
cd plx-token
$env:JETTON_MINTER_ADDRESS = "kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV"
$env:JETTON_ADMIN = "plx-deployer-v2"
$env:JETTON_IMAGE = "ipfs://<CID>"   # from metadata/plx-logo-ipfs.json after pin
# or gateway HTTPS for wallet compatibility:
# $env:JETTON_IMAGE = "https://ipfs.plx.foundation/ipfs/<CID>"
acton run refresh-metadata-testnet
```

### Option B — interactive

```bash
acton run jetton-change-metadata --net testnet
```

### Verify

```bash
acton run jetton-info --net testnet
# or
curl -s "https://testnet.tonapi.io/v2/jettons/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV" | jq .metadata.image
curl -I "https://ipfs.plx.foundation/ipfs/<CID>"
```

Open [Tonviewer testnet minter](https://testnet.tonviewer.com/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV) and confirm the logo loads.

## Image URL requirements

- **`ipfs://{CID}`** (preferred for new deploys) or **HTTPS** gateway URL.
- No `data:` URLs on-chain.
- Publicly reachable (`curl -I` → `200` on gateway).
- Square PNG/WebP, ideally **256×256** or **512×512**, **≤ 256 KB** (Tonkeeper guidance).

## Mainnet (live)

Mainnet minter: `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`

On-chain `image` at deploy: `https://plx.foundation/plx-logo.png` (migrate to `ipfs://` via pin script + `change-metadata`)

Verify:

```bash
curl -s "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | jq .metadata.image
curl -I https://plx.foundation/plx-logo.png
```

Tonkeeper: mainnet → add custom jetton → paste **minter** address (not your wallet). Allow 15–60 minutes for image cache.

To update metadata after deploy, use the same `jetton-change-metadata` / refresh script flow with `--net mainnet` and `JETTON_ADMIN=plx-deployer-v2-mainnet`. See `docs/MAINNET-CHECKLIST.md`.

## Smoke checklist (IPFS integration)

| Check | Expected |
|-------|----------|
| `GET /health/db` | `"db":"connected"` |
| `GET /public/deployed-tokens` | `image_url` uses `ipfs.plx.foundation` when pinned |
| Upload `POST .../token-image` | Response includes `ipfs_cid`, `ipfs_uri` |
| Dashboard `/dashboard` | Logo loads from gateway URL |
| TonAPI after deploy | `metadata.image` = `ipfs://...` |
