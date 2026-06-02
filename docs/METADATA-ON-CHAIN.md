# On-chain jetton metadata (logo / icon)

PLX and every jetton deployed through Phalanx store **name, symbol, decimals, description, and image** in the minter's **on-chain metadata cell** (TEP-64 dictionary). Wallets and explorers (Tonviewer, Tonkeeper, TonAPI) read that cell — not your website form or local `metadata/` folder.

## Why the testnet icon did not change

Changing any of these **does not** update what Tonviewer shows:

- Uploading a logo in the **toolkit build wizard** (that only affects *your* draft deployment).
- Editing `metadata/logo.png` locally without an on-chain transaction.
- Replacing the file on GitHub **without** sending `ChangeMinterMetadata` (explorers may also cache the old image URL for hours).

The live PLX testnet minter (`kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV`) still points to whatever `image` key was set at deploy or last metadata update. Today that is:

```text
https://raw.githubusercontent.com/phalanx-foundation/plx-token/master/metadata/logo.png
```

TonAPI caches previews — even after you update on-chain, allow **15–60 minutes** or use a **new URL** (e.g. `https://plx.foundation/plx-logo.png`) to bust caches.

## How to update PLX testnet metadata (operator)

**Requirements:** Acton CLI, testnet minter **admin** wallet (`plx-deployer-v2`), ~0.05 TON for gas.

### Option A — refresh script (recommended)

```powershell
cd plx-token
$env:JETTON_MINTER_ADDRESS = "kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV"
$env:JETTON_ADMIN = "plx-deployer-v2"
$env:JETTON_IMAGE = "https://plx.foundation/plx-logo.png"
# optional overrides:
# $env:JETTON_NAME = "Phalanx"
# $env:JETTON_SYMBOL = "PLX"
# $env:JETTON_DESCRIPTION = "..."
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
```

Open [Tonviewer testnet minter](https://testnet.tonviewer.com/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV) and confirm the logo loads.

## Image URL requirements

- **HTTPS** only (no `data:` URLs on-chain).
- Publicly reachable (`curl -I` → `200`).
- Square PNG/WebP, ideally **256×256** or **512×512**, **≤ 256 KB** (Tonkeeper guidance).
- Prefer a stable CDN URL (`plx.foundation`, GitHub raw, or IPFS) you control.

## Mainnet (live)

Mainnet minter: `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`

On-chain `image` at deploy: `https://plx.foundation/plx-logo.png`

Verify:

```bash
curl -s "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | jq .metadata.image
curl -I https://plx.foundation/plx-logo.png
```

Tonkeeper: mainnet → add custom jetton → paste **minter** address (not your wallet). Allow 15–60 minutes for image cache.

To update metadata after deploy, use the same `jetton-change-metadata` / refresh script flow with `--net mainnet` and `JETTON_ADMIN=plx-deployer-v2-mainnet`. See `docs/MAINNET-CHECKLIST.md`.
