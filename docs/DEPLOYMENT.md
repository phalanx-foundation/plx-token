# Deployment Guide

## Prerequisites

| Requirement | Version | Install |
|---|---|---|
| Linux or macOS (or WSL2 on Windows) | recent | n/a |
| `curl`, `git` | any | system package manager |
| Acton CLI | 1.0.0+ | `curl -LsSf https://github.com/ton-blockchain/acton/releases/latest/download/acton-installer.sh \| sh` |

After installing Acton, restart your shell or run `source ~/.acton/bin/env`. Verify with `acton --version`.

## Project Setup

```bash
git clone https://github.com/phalanx-foundation/plx-token.git
cd plx-token
acton doctor   # verifies network connectivity & toolchain
acton build
acton test
```

You should see **60 passing tests**.

## Wallet Setup

The deployment uses **6 wallets**, all controlled by you:

| Wallet | Purpose | Funded with TON? |
|---|---|---|
| `plx-deployer` | Deploys contracts, mints initial supply, signs admin txs | Yes (~5 TON for mainnet) |
| `plx-treasury` | Holds 250M PLX | Optional (for storage rent on jetton wallet, ~0.05 TON) |
| `plx-lp` | Holds 400M PLX (later → DEX LP) | Optional |
| `plx-community` | Holds 200M PLX | Optional |
| `plx-marketing` | Holds 50M PLX | Optional |
| `plx-vesting-beneficiary` | Receives vesting unlocks | Optional (until first claim) |

```bash
for n in plx-deployer plx-treasury plx-lp plx-community plx-marketing plx-vesting-beneficiary; do
  acton wallet new --local --name "$n" --version v5r1 --secure false
done
```

> **Note for the live Phalanx Foundation testnet:** the original `plx-deployer`
> wallet was retired during a 2026-05-20 security drill and is replaced by
> `plx-deployer-v2` (address
> `kQBg9RFEVaQIh3xVonBxCnIb2Vw19y-rSD4uO1LR0eNH4zT2`). If you are operating
> the live testnet, set `PLX_DEPLOYER=plx-deployer-v2`, `PLX_ADMIN=plx-deployer-v2`,
> and `PLX_CALLER=plx-deployer-v2` in your `.env` so ops scripts pick it up.
> Fresh clones can ignore this and use `plx-deployer` as in the snippet above.

Wallet metadata is saved to `wallets.toml` (gitignored). Mnemonics are AES-encrypted with a project key.

> **CRITICAL**: Back up `wallets.toml` and the mnemonics shown at creation time to a secure offline location. If you lose them, you lose access to all PLX you control.

## Testnet Deployment

### Step 1: Faucet

```bash
acton wallet airdrop plx-deployer
acton wallet airdrop plx-deployer   # 2 max per 24h per IP
```

You should now have ~4 TON on the deployer.

### Step 2: Deploy distribution

```bash
PLX_TREASURY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-treasury") | .address') \
PLX_LP=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-lp") | .address') \
PLX_COMMUNITY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-community") | .address') \
PLX_MARKETING=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-marketing") | .address') \
PLX_BENEFICIARY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-vesting-beneficiary") | .address') \
PLX_VESTING_START=$(date +%s) \
acton script scripts/deploy-distribution.tolk --net testnet
```

The script:

1. Deploys `JettonMinter` with PLX metadata
2. Mints 400M to LP, 250M to Treasury, 200M to Community, 50M to Marketing
3. Deploys `TeamVesting` contract with 6-month duration
4. Mints 100M to vesting contract (locks them)
5. Prints all addresses

Save the printed addresses — you'll reference them in `docs/TOKENOMICS.md` and external listings.

### Step 3: Verify on Tonviewer

```
https://testnet.tonviewer.com/<MINTER_ADDRESS>
https://testnet.tonviewer.com/<VESTING_ADDRESS>
```

Check:
- Total supply = 1,000,000,000 × 10^9 = 1,000,000,000,000,000,000 nano-PLX
- Metadata fields visible (name, symbol, image, description)
- All 5 holder wallets show their balances

### Step 4: Test interactions

Use Tonkeeper testnet mode:
1. Switch to testnet (Settings → Developer → Testnet)
2. Add custom token using minter address
3. Send PLX between wallets
4. Burn some PLX from treasury (deflationary test)

## Mainnet Deployment

> **Do NOT proceed unless** you have:
>
> - At least **5 TON** in your deployer wallet on mainnet
> - Verified all 60 tests pass
> - Reviewed `contracts/*.tolk` for any production-only changes
> - Backed up `wallets.toml` to offline secure storage
> - Decided on whether to **drop admin** after distribution (recommended)

### Step M1: Mainnet wallets

If your testnet wallet names exist, **rename them or create separate mainnet wallets**:

```bash
acton wallet new --local --name plx-deployer-mainnet --version v5r1 --secure false
# repeat for the other 5 wallets if you want mainnet ↔ testnet separation
```

Fund `plx-deployer-mainnet` with **at least 5 TON** from a real source (CEX withdrawal, swap, etc.).

### Step M2: Run deploy

```bash
PLX_DEPLOYER=plx-deployer-mainnet \
PLX_TREASURY=<mainnet treasury address> \
PLX_LP=<mainnet lp address> \
PLX_COMMUNITY=<mainnet community address> \
PLX_MARKETING=<mainnet marketing address> \
PLX_BENEFICIARY=<mainnet beneficiary address> \
PLX_VESTING_START=$(date +%s) \
acton script scripts/deploy-distribution.tolk --net mainnet
```

Expect ~3 TON to be consumed (deploy + 5 mints + vesting deploy + 1 mint).

### Step M3: Verify

- Tonviewer mainnet: `https://tonviewer.com/<MINTER_ADDRESS>`
- Tonscan mainnet: `https://tonscan.org/address/<MINTER_ADDRESS>`
- Acton verifier: `acton verify JettonMinter --net mainnet` (publishes source to TON Verifier)

### Step M4: Post-deploy hardening

After verifying everything is correct:

```bash
# Optional but recommended: drop admin to make supply non-mintable forever
acton run jetton-change-admin   # propose null admin (or use scripts/drop-admin.tolk)
```

This is permanent — only do this **after** the full distribution is minted and you have publicly committed to a fixed supply.

### Step M5: Add to wallets, list on DEX

1. Submit token to Ston.fi / DeDust for listing
2. Provide initial liquidity from `plx-lp` wallet (pair PLX/TON)
3. Submit metadata to Tonkeeper / MyTonWallet for proper UI display
4. Apply to TON Foundation token whitelist

See `docs/MAINNET-CHECKLIST.md` for the full operational checklist.

## Useful commands

```bash
acton wallet list --balance                    # show all wallets and balances
acton run jetton-info                          # query minter info
acton run jetton-mint                          # mint additional jettons (interactive)
acton run jetton-transfer                      # transfer jettons (interactive)
acton retrace <TX_HASH>                        # replay a transaction trace
acton verify JettonMinter --net testnet        # publish source to TON Verifier
```

## Troubleshooting

| Error | Fix |
|---|---|
| `Faucet returned error 429` | Wait 24h, or use a different IP |
| `NotEnoughGas` (exit code 48) | Increase `--value` on the operation |
| Wallet not found | Check `wallets.toml` and `acton wallet list` |
| Contract reverts on deploy | Check `acton retrace <tx>` for the failed step |
| Address mismatch testnet vs mainnet | Wallet derivation is identical; only network differs. Same wallet works on both. |
