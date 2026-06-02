# Mainnet Deployment Checklist

Use this as the single source of truth before pushing PLX to TON mainnet. Tick each box.

## Pre-flight (1–2 days before)

- [x] All tests pass: `acton test` (72+ at deploy time)
- [x] Lint clean: `acton check`
- [x] Format clean: `acton fmt --check`
- [x] CI green on `master` branch
- [x] Reviewed every contract file for hardcoded testnet artifacts (none found)
- [x] Reviewed `contracts/sharding.tolk` for `MY_WORKCHAIN = BASECHAIN` (correct for mainnet)
- [x] Logo (`metadata/logo.png`) is final, 256×256 or 512×512 PNG, transparent background
- [x] `metadata/phalanx-metadata.json` has correct values (name, symbol, image URL)
- [x] Image URL is publicly accessible at `https://plx.foundation/plx-logo.png`

## Funding

- [x] Mainnet deployer wallet created and **mnemonic backed up offline**
- [x] Deployer wallet funded (≥ 5 TON on mainnet)
- [x] All 5 distribution wallet addresses confirmed (treasury, lp, community, marketing, beneficiary)
- [x] Each distribution wallet's address double-checked against `acton wallet list --net mainnet`

## Deploy

- [x] Set `PLX_VESTING_START` (used: `1780381461`)
- [x] Run `acton script scripts/deploy-distribution.tolk --net mainnet`
- [x] Saved addresses — see [`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md)
- [x] Deploy log saved: `~/projects/plx-acton/.deploy-mainnet.log`
- [x] PaymentSplitter deployed (`deploy-splitter.tolk`, 0.5 TON deploy fee)

## Verify (immediately after deploy)

- [x] Tonviewer minter exists
- [x] Total supply = `1000000000000000000` (1B × 10^9)
- [x] `MINTABLE = true` (admin not yet dropped)
- [x] Distribution balances: LP 400M, Treasury 250M, Community 200M, Marketing 50M, Vesting 100M
- [x] Metadata + logo URL on-chain (`https://plx.foundation/plx-logo.png`)

## Source verification

- [ ] `acton verify JettonMinter --net mainnet`
- [ ] `acton verify JettonWallet --net mainnet`
- [ ] `acton verify TeamVesting --net mainnet`
- [ ] `acton verify PaymentSplitter --net mainnet`
- [ ] Verified badge on Tonviewer

## Documentation update

- [x] Mainnet addresses in `README.md`, `docs/TOKENOMICS.md`
- [x] [`docs/MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md) created
- [x] [`docs/TRANSPARENCY.md`](TRANSPARENCY.md) mainnet registry
- [ ] Commit & push docs update (when ready)

## Optional but recommended hardening

- [ ] After 24–48 hours monitoring, run drop-admin:
  ```bash
  PLX_CONFIRM_DROP_ADMIN=1 acton script scripts/drop-admin.tolk --net mainnet
  ```
  > **Irreversible.** Only when distribution is final.

## Liquidity & Listing (after mainnet deploy)

- [ ] Initial liquidity on Ston.fi (PLX/TON from LP wallet)
- [ ] DeDust (optional)
- [x] Tonkeeper `ton-assets` PR opened — https://github.com/tonkeeper/ton-assets/pull/5468 (merge pending)
- [ ] MyTonWallet listing
- [ ] TON Foundation token whitelist (if applicable)

## Marketing & Community

- [x] Addresses on GitHub README + deployment record
- [ ] Website plx.foundation `/plx-token` mainnet section
- [ ] Tweet / Telegram announcement
- [ ] LinkedIn update

## Audit trail

- [ ] Tag `mainnet-deploy-v1.0.0` on GitHub
- [ ] Encrypted offline backup of mainnet `wallets.toml`
- [x] Deploy log on server (private)

---

## Emergency rollback

If something goes catastrophically wrong **before** dropping admin:

- Mint can be paused operationally by simply not running mint scripts
- Admin can be transferred to an emergency multisig via `ChangeMinterAdmin`
- Vesting cannot be paused once funded (only revoked)

There is **no rollback after dropping admin**.
