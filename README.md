# Phalanx (PLX)

[![CI](https://github.com/phalanx-foundation/plx-token/actions/workflows/contracts.yml/badge.svg)](https://github.com/phalanx-foundation/plx-token/actions/workflows/contracts.yml)
[![Built with Acton](https://img.shields.io/badge/built%20with-Acton-blue)](https://ton-blockchain.github.io/acton/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> Utility token for the **Phalanx Foundation** ecosystem on the TON blockchain.

Phalanx (PLX) is a TEP-74 standard Jetton with **mintable**, **burnable**, and **transferable owner** capabilities, plus an on-chain **linear vesting contract** for team allocation. Built with [Acton](https://ton-blockchain.github.io/acton/) and [Tolk](https://docs.ton.org/develop/tolk).

<p align="center">
  <img src="metadata/logo.png" alt="Phalanx PLX" width="200" />
</p>

## Token Info

| Field | Value |
|---|---|
| Name | Phalanx |
| Symbol | PLX |
| Decimals | 9 |
| Total Supply | 1,000,000,000 PLX (1 billion) |
| Standard | TEP-74 Jetton + TEP-89 metadata |
| Blockchain | TON (Basechain, workchain 0) |

## Distribution

| % | Allocation | Purpose |
|---:|---:|---|
| 40% | 400M PLX | Liquidity Provision (DEX) |
| 25% | 250M PLX | Treasury |
| 20% | 200M PLX | Community Rewards & Airdrops |
| 10% | 100M PLX | Team (vested 6 months linear, on-chain) |
| 5% | 50M PLX | Marketing & Partnerships |

See [docs/TOKENOMICS.md](docs/TOKENOMICS.md) for full details and current testnet addresses.

## Testnet Deployment (live)

| Contract / Role | Address |
|---|---|
| **Jetton Minter** | `kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV` |
| **Team Vesting** | `kQDNPoiPbKXwjt4i9SqtBmvbUlMgWz1jCR7M5Uwjj5fI8t1l` |
| **Active deployer / minter admin** | `kQBg9RFEVaQIh3xVonBxCnIb2Vw19y-rSD4uO1LR0eNH4zT2` (wallet `plx-deployer-v2`) |
| **Retired deployer (security drill 2026-05-20)** | `kQB1GGwuoPV1vS2DjEg-weTPy5_HQU4ipqQm6KO05EyqEizN` |

Verify on [Tonviewer testnet](https://testnet.tonviewer.com/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV) or [Tonscan testnet](https://testnet.tonscan.org/address/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV).

Genesis tx: [`17879144...d1109`](https://testnet.tonscan.org/tx/17879144d22c2c6e69209515ebb19563a7a76b6b17d44d7f8c28cca6f4dd1109).
Rotation drill detail: [docs/TESTNET-DEPLOYMENT-RECORD.md](docs/TESTNET-DEPLOYMENT-RECORD.md#security-drill-deployer-rotation-2026-05-20).

## Repository Structure

```
plx-token/
├── contracts/              # Tolk source contracts
│   ├── JettonMinter.tolk   # TEP-74 minter (mintable, owner-transferable, burnable via wallet)
│   ├── JettonWallet.tolk   # TEP-74 per-holder wallet
│   ├── TeamVesting.tolk    # Linear vesting (6 months) for team allocation
│   ├── messages.tolk       # TLB message structs (opcodes)
│   ├── storage.tolk        # Contract storage layouts
│   ├── errors.tolk         # Error code enum
│   ├── fees-management.tolk # Gas/storage fee math
│   ├── jetton-utils.tolk   # Wallet address derivation
│   └── sharding.tolk       # Workchain & shard constants
├── tests/                  # Native Tolk tests (60 passing)
├── scripts/                # Deployment & operational scripts
├── wrappers/               # Auto-generated TS-style wrappers
├── metadata/               # On-chain metadata (logo, JSON)
├── docs/                   # TOKENOMICS, DEPLOYMENT, etc.
└── Acton.toml              # Project manifest
```

## Quick Start

### Prerequisites

- Linux/macOS (or WSL2 on Windows)
- `curl`, `git`
- ~5 minutes

```bash
# Install Acton CLI
curl -LsSf https://github.com/ton-blockchain/acton/releases/latest/download/acton-installer.sh | sh

# Clone repo
git clone https://github.com/phalanx-foundation/plx-token.git
cd plx-token
```

### Build & Test

```bash
acton build           # compile all contracts
acton test            # run 60 tests
acton check --fix     # lint + auto-format
```

### Deploy to Testnet (full distribution)

> If you are running this on a **fresh** clone, the wallet name `plx-deployer`
> below is just a convention — pick whatever you like. On the **live testnet**
> currently maintained by Phalanx Foundation, the active operator wallet is
> `plx-deployer-v2` (post rotation drill); set `PLX_DEPLOYER=plx-deployer-v2`
> in your `.env` to make the ops scripts use it.

```bash
# Generate wallets (deployer + 5 distribution wallets)
for n in plx-deployer plx-treasury plx-lp plx-community plx-marketing plx-vesting-beneficiary; do
  acton wallet new --local --name $n --version v5r1 --secure false
done

# Request testnet TON
acton wallet airdrop plx-deployer
acton wallet airdrop plx-deployer    # one more time (limit 2/24h)

# Deploy minter + vesting + initial mint to all wallets
PLX_TREASURY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-treasury") | .address') \
PLX_LP=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-lp") | .address') \
PLX_COMMUNITY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-community") | .address') \
PLX_MARKETING=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-marketing") | .address') \
PLX_BENEFICIARY=$(acton wallet list --json | jq -r '.wallets[] | select(.name=="plx-vesting-beneficiary") | .address') \
PLX_VESTING_START=$(date +%s) \
acton script scripts/deploy-distribution.tolk --net testnet
```

### Deploy to Mainnet

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the production checklist.

## Documentation

- [Tokenomics](docs/TOKENOMICS.md) — distribution, vesting schedule, treasury policy
- [Transparency](docs/TRANSPARENCY.md) — wallet registry, movement policy, audit trail
- [Deployment](docs/DEPLOYMENT.md) — testnet/mainnet step-by-step
- [Architecture](docs/ARCHITECTURE.md) — contract design and message flows
- [Mainnet Checklist](docs/MAINNET-CHECKLIST.md) — production deploy gates
- [Testnet Deployment Record](docs/TESTNET-DEPLOYMENT-RECORD.md) — live testnet evidence
- [Contributing](CONTRIBUTING.md) — guide for outside contributors

## Built By

The **Phalanx Foundation** team. Find us on [GitHub](https://github.com/phalanx-foundation).

## License

MIT — see [LICENSE](LICENSE).
