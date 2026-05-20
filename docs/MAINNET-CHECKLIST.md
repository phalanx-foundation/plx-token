# Mainnet Deployment Checklist

Use this as the single source of truth before pushing PLX to TON mainnet. Tick each box.

## Pre-flight (1–2 days before)

- [ ] All 60 tests pass: `acton test`
- [ ] Lint clean: `acton check` (no errors, only acceptable warnings)
- [ ] Format clean: `acton fmt --check`
- [ ] CI green on `master` branch
- [ ] Reviewed every contract file for hardcoded testnet artifacts (none found)
- [ ] Reviewed `contracts/sharding.tolk` for `MY_WORKCHAIN = BASECHAIN` (correct for mainnet)
- [ ] Logo (`metadata/logo.png`) is final, 256×256 or 512×512 PNG, transparent background
- [ ] `metadata/phalanx-metadata.json` has correct values (name, symbol, image URL)
- [ ] Image URL is publicly accessible (`curl -I` returns 200) at the GitHub raw URL

## Funding

- [ ] Mainnet deployer wallet created and **mnemonic backed up offline** (paper, hardware, or encrypted USB)
- [ ] Deployer wallet has **at least 5 TON** (deploys + 5 mints + vesting deploy + 1 vesting mint ≈ 3.1 TON, buffer for retries)
- [ ] All 5 distribution wallet addresses confirmed (treasury, lp, community, marketing, beneficiary)
- [ ] Each distribution wallet's address has been double-checked against `acton wallet list`

## Deploy

- [ ] Set `PLX_VESTING_START` to the desired start timestamp (defaults to `date +%s`)
- [ ] Run `acton script scripts/deploy-distribution.tolk --net mainnet`
- [ ] Save the printed addresses to a secure note:
  - [ ] `PLX_MINTER_ADDRESS`
  - [ ] `PLX_VESTING_ADDRESS`
  - [ ] All 5 jetton wallet addresses
- [ ] Save the deployment tx hash from the log

## Verify (immediately after deploy)

- [ ] Open `https://tonviewer.com/<MINTER_ADDRESS>` — confirms minter exists
- [ ] Total supply = `1000000000000000000` (1B × 10^9)
- [ ] `MINTABLE = true` (will set to false later when admin is dropped)
- [ ] Each distribution wallet balance matches expected:
  - [ ] LP: 400,000,000 PLX
  - [ ] Treasury: 250,000,000 PLX
  - [ ] Community: 200,000,000 PLX
  - [ ] Marketing: 50,000,000 PLX
  - [ ] Vesting: 100,000,000 PLX (in vesting contract's jetton wallet)
- [ ] Metadata fields render correctly in Tonviewer
- [ ] Logo image loads in Tonviewer

## Source verification

- [ ] `acton verify JettonMinter --net mainnet` — publishes source to TON Verifier
- [ ] `acton verify JettonWallet --net mainnet`
- [ ] `acton verify TeamVesting --net mainnet`
- [ ] On Tonviewer, the contracts show "verified" badge

## Documentation update

- [ ] Replace testnet addresses in `README.md` with mainnet addresses
- [ ] Replace testnet addresses in `docs/TOKENOMICS.md` with mainnet addresses
- [ ] Add mainnet deployment tx hash to `docs/TOKENOMICS.md`
- [ ] Commit & push docs update

## Optional but recommended hardening

- [ ] After 24–48 hours of monitoring, run drop-admin script to make supply permanently fixed:
  ```bash
  acton run jetton-change-admin   # send DropMinterAdmin (or use direct script)
  ```
  > **Irreversible.** Only do this when you're certain the distribution is final.

## Liquidity & Listing (after mainnet deploy)

- [ ] Provide initial liquidity on Ston.fi: pair PLX/TON
  - Suggested ratio: 100k PLX × X TON (decide opening price)
  - Use `plx-lp` wallet (has 400M PLX)
- [ ] Provide initial liquidity on DeDust (alternative DEX)
- [ ] Submit token to Tonkeeper for default-asset listing
- [ ] Submit token to MyTonWallet
- [ ] Apply to TON Foundation token whitelist

## Marketing & Community

- [ ] Pin contract addresses on Phalanx Foundation website / GitHub readme
- [ ] Tweet announcement with minter address + Tonviewer link
- [ ] Telegram announcement
- [ ] Update Phalanx Foundation LinkedIn
- [ ] Reach out to TON ecosystem partners

## Audit trail

- [ ] Tag the deploy commit with `mainnet-deploy-v1.0.0` and add a release on GitHub
- [ ] Save mainnet `wallets.toml` to encrypted offline backup
- [ ] Save deploy log (`.deploy-mainnet.log`) to private repo or password manager

---

## Emergency rollback

If something goes catastrophically wrong **before** dropping admin:

- Mint can be paused operationally by simply not running mint scripts
- Admin can be transferred to an emergency multisig via `ChangeMinterAdmin`
- Vesting cannot be paused once funded (only revoked)

There is **no rollback after dropping admin**. Make sure everything is correct before that step.
