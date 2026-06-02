# Mainnet Deployment Record

> Live deployment evidence for Phalanx (PLX) on TON **mainnet** (June 2026).
> Full testnet history: [`TESTNET-DEPLOYMENT-RECORD.md`](TESTNET-DEPLOYMENT-RECORD.md).

## Contracts (mainnet, live)

| Contract | Address (EQ, bounceable) | Address (UQ, Tonkeeper) | Explorer |
|---|---|---|---|
| **Jetton Minter** | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` | same raw — use EQ in explorers | [Tonviewer](https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS) · [Tonscan](https://tonscan.org/address/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS) |
| **Team Vesting** | `EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l` | — | [Tonviewer](https://tonviewer.com/EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l) |
| **PaymentSplitter** | `EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv` | — | [Tonviewer](https://tonviewer.com/EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv) |

**Import PLX in Tonkeeper (mainnet):** Settings → mainnet → add custom jetton → paste **minter** address `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` (not your personal wallet address).

**On-chain metadata image:** `https://plx.foundation/plx-logo.png` (see [`METADATA-ON-CHAIN.md`](METADATA-ON-CHAIN.md)).

## Distribution wallets (mainnet)

Six operational wallets (`acton wallet new --version v5r1`) — each has its **own** 24-word mnemonic in `wallets.toml` on the deploy server. `UQ…` = non-bounceable (Tonkeeper); `EQ…` = bounceable (CLI/explorer); **same account**.

| Role | Wallet name (Acton) | UQ (Tonkeeper) | EQ (docs/CLI) |
|---|---|---|---|
| Deployer / minter admin (temporary) | `plx-deployer-v2-mainnet` | `UQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anhSm` | `EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj` |
| Treasury (250M PLX) | `plx-treasury-mainnet` | `UQBB…KwtS` | `EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX` |
| LP (400M PLX) | `plx-lp-mainnet` | `UQAi…eyEC` | `EQAiQ41f7R5qzKsoimbujtYdy0bRKW_7Fb0rV5Z4Lw6gr3zH` |
| Community (200M PLX) | `plx-community-mainnet` | — | `EQD1XDv0Awjx0GUVv6YQYYnvEmjcKJ9iEBjvtHPM2nWML-q9` |
| Marketing (50M PLX) | `plx-marketing-mainnet` | `UQDB…To6_` | `EQDB9yVhkPvEhMFo90fqHWzqYj2mESAlwObMbA6LX7fETtN6` |
| Vesting beneficiary | `plx-vesting-beneficiary-mainnet` | `UQB5…LYvC` | `EQB5_ndfsF6gSuMDYYA4Uq2R26jPRzEsvFK-glI9VwbzLdYH` |

| Role | Expected PLX balance | Notes |
|---|---:|---|
| LP | 400,000,000 | Reserved for Ston.fi / DeDust |
| Treasury | 250,000,000 | Ops, buyback, toolkit treasury slice |
| Community | 200,000,000 | Rewards / airdrops |
| Marketing | 50,000,000 | Listings, campaigns |
| Vesting contract | 100,000,000 | Locked in `TeamVesting` jetton wallet |
| PaymentSplitter jetton wallet | 0 PLX | Fills only when Toolkit PLX rail is used |

**Total supply on-chain:** `1,000,000,000,000,000,000` nano-PLX = 1,000,000,000 PLX.

### Why TonAPI shows **5 holders**, not 6

Genesis mint created **five jetton wallets with PLX balance**:

| # | Holder (jetton wallet owner) | PLX |
|---|------------------------------|-----|
| 1 | LP wallet | 400M |
| 2 | Treasury wallet | 250M |
| 3 | Community wallet | 200M |
| 4 | **TeamVesting contract** (not beneficiary wallet yet) | 100M |
| 5 | Marketing wallet | 50M |

**Not counted as holders** (balance 0 PLX):

- **Deployer** — minter admin only, received no PLX mint
- **Vesting beneficiary** — personal wallet; team tokens sit in the **vesting contract’s** jetton wallet until `claim-vesting`
- **PaymentSplitter** — no genesis PLX; only receives PLX when Toolkit users pay

Ops docs sometimes list **six named wallets** in `wallets.toml` (deployer + 5 recipients). That is wallet inventory, not holder count on the jetton.

## Vesting contract live state

```
beneficiary  = EQB5_ndfsF6gSuMDYYA4Uq2R26jPRzEsvFK-glI9VwbzLdYH
admin        = EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj (deployer at deploy time)
totalAmount  = 100,000,000,000,000,000 nano-PLX (= 100M PLX)
startTime    = 1780381461
duration     = 15,552,000 seconds (180 days)
```

## Deploy economics (TON, not PLX)

| Step | TON sent | Purpose |
|---|---:|---|
| Deploy JettonMinter | ~0.5 TON | Contract creation (`deploy-distribution.tolk`) |
| Deploy TeamVesting + mints | variable | Vesting deploy + 5 distribution mints + 100M to vesting |
| Deploy PaymentSplitter | **0.5 TON** | Contract creation only (`deploy-splitter.tolk` line `value: ton("0.5")`) — **not** a PLX allocation |

The 0.5 TON on the splitter address is **rent/gas for deploying the splitter smart contract**, not a tokenomics transfer. No genesis PLX was minted to the splitter.

## Genesis / ops notes

- Distribution completed after a vesting-step retry via `scripts/finish-vesting.tolk` (PowerShell `date` issue on first run).
- Deploy log (private): `~/projects/plx-acton/.deploy-mainnet.log` on `dev@100.100.168.168`.
- **Minter admin not yet dropped** — supply still technically mintable until `scripts/drop-admin.tolk` with `PLX_CONFIRM_DROP_ADMIN=1`.

## Managing wallets in Tonkeeper

| Goal | Action |
|---|---|
| View treasury/LP balances | Tonviewer links above, or watch-only address in Tonkeeper |
| Spend from treasury/LP | Import **that wallet's** 24 words (from backup or server `wallets.toml`) — deployer mnemonic alone is not enough |
| Add PLX token display | Custom jetton → minter `EQCbaUJqi…` on **mainnet** |

## Test suite (pre-deploy)

```
acton test
72 passed (7 files) — at mainnet deploy time
```

## Token list submission (prepared)

See [`docs/TONKEEPER-ASSET-SUBMISSION.md`](TONKEEPER-ASSET-SUBMISSION.md) for Tonkeeper `ton-assets` PR fields.

---

*Deployed by Phalanx Foundation using [Acton](https://ton-blockchain.github.io/acton/) + [Tolk](https://docs.ton.org/develop/tolk) on TON mainnet.*
