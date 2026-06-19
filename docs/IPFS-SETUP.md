# IPFS setup — Pinata (pin) + Cloudflare IPFS Gateway (serve)

Token logos are pinned with **Pinata** and served through a **Cloudflare IPFS Gateway** at `https://ipfs.plx.foundation/ipfs/{CID}`.

## 1. Cloudflare IPFS Gateway (read-only)

1. Cloudflare Dashboard → **Web3** → **IPFS Gateways** → **Create gateway**.
2. Type: **DNSLink** (restricted gateway is fine for token assets).
3. Hostname: `ipfs.plx.foundation` (zone `plx.foundation` must be on Cloudflare).
4. Set env everywhere:
   - `IPFS_GATEWAY_HOST=ipfs.plx.foundation`
   - `NEXT_PUBLIC_IPFS_GATEWAY_HOST=ipfs.plx.foundation` (Cloudflare Pages)

Free tier includes **50 GB/month** bandwidth — sufficient for jetton logos.

Verify after first pin:

```bash
curl -I "https://ipfs.plx.foundation/ipfs/<CID>"
```

## 2. Pinata (upload / pin)

1. [pinata.cloud](https://pinata.cloud) → API Keys → create JWT.
2. Set in root `.env` and deploy to Ubuntu API (`~/services/plx-toolkit-api/.env`):
   - `PINATA_JWT=...`
   - `TOKEN_IMAGE_STORAGE=ipfs` (or `dual` for GitHub backup)
3. Deploy API prod:

```powershell
powershell -File "D:\DATA TOOLS\PLX-ACTON\toolkit-staging\scripts\deploy-api-acton.ps1"
```

## 3. Pin PLX native logo (one-time)

```powershell
powershell -File "D:\DATA TOOLS\PLX-ACTON\.scripts\ops\load-env.ps1"
python "D:\DATA TOOLS\PLX-ACTON\scripts\pin-plx-logo-ipfs.py"
```

Updates [`metadata/plx-logo-ipfs.json`](../metadata/plx-logo-ipfs.json). Then refresh on-chain metadata:

```powershell
$env:JETTON_MINTER_ADDRESS = "<testnet-or-mainnet-minter>"
$env:JETTON_ADMIN = "plx-deployer-v2"
$env:JETTON_IMAGE = "ipfs://<CID>"
acton run refresh-metadata-testnet   # or jetton-change-metadata --net mainnet
```

## 4. Smoke checklist

| Check | Command / URL |
|-------|----------------|
| API DB | `curl https://api.plx.foundation/health/db` |
| Deployed tokens | `GET /public/deployed-tokens` — `image_url` uses gateway |
| Upload | POST `/deployments/{id}/token-image` → metadata has `ipfs_cid`, `ipfs_uri` |
| Dashboard | `/dashboard` — logo loads from `ipfs.plx.foundation` |
| On-chain | TonAPI `metadata.image` = `ipfs://...` after deploy |

See also [`METADATA-ON-CHAIN.md`](METADATA-ON-CHAIN.md).
