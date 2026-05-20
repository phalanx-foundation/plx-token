# Phalanx (PLX)

[![CI](https://github.com/phalanx-foundation/plx-token/actions/workflows/contracts.yml/badge.svg)](https://github.com/phalanx-foundation/plx-token/actions/workflows/contracts.yml)
[![Built with Acton](https://img.shields.io/badge/built%20with-Acton-blue)](https://ton-blockchain.github.io/acton/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> Utility token for the **Phalanx Foundation** ecosystem on the TON blockchain.

Phalanx (PLX) is a TEP-74 standard Jetton with **mintable**, **burnable**, and **transferable owner** capabilities, plus an on-chain **linear vesting contract** for team allocation. Built with [Acton](https://ton-blockchain.github.io/acton/) and [Tolk](https://docs.ton.org/develop/tolk).

<p align="center">
  <img src="metadata/logo.png" alt="Phalanx PLX" width="200" />
</p>

---

## Mission & Vision

Phalanx Foundation is an open-source initiative building **on-chain infrastructure for the open economy**. We design an ecosystem of audited, modular, reusable building blocks — starting on TON — so that any project, builder, or community can deploy production-grade smart contracts without writing a single line of code from scratch. Our first product is the **Phalanx Tokenization Toolkit**: a launchpad of pre-tested Jetton, vesting, and governance contracts that turns weeks of engineering into a verifiable deployment in minutes. PLX is the connective tissue of this ecosystem — granting discounted access to premium services, voting rights over which primitives we build next, and a share of network revenue for stakers.

---

## What We're Building

The first product shipping from Phalanx Foundation is the **Tokenization Toolkit** — a self-service launchpad where any TON project can deploy a Jetton with on-chain vesting, optional multisig admin, and configurable governance hooks in minutes rather than months. Today, projects launching on TON typically fork unmaintained reference code, modify it without a formal review, deploy by hand, and hope nothing breaks. Phalanx removes this risk by providing one audited, battle-tested foundation that anyone can use, with transparent deployment costs and verifiable on-chain results. PLX integrates naturally: customers paying with PLX receive a 50% discount on deployment fees, a portion of collected fees is permanently burned to reduce circulating PLX supply, and PLX stakers earn a share of network revenue. This is utility driven by real demand from real builders — not speculation.

Beyond the launchpad, our roadmap covers a governance module that lets PLX holders vote on which new contract templates to build, a developer SDK for embedding PLX into third-party TON applications, and — once revenue, traction, and ecosystem maturity justify it — expansion to additional chains where the same primitives are needed.

---

## Token Info

| Field | Value |
|---|---|
| Name | Phalanx |
| Symbol | PLX |
| Decimals | 9 |
| Total Supply | 1,000,000,000 PLX (1 billion, fixed) |
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

After the initial distribution and a 24–48 hour observation window, the **minter admin will be permanently dropped** via an irreversible on-chain transaction, locking total supply at 1B PLX forever — no party (including Phalanx Foundation itself) will be able to mint additional PLX.

See [docs/TOKENOMICS.md](docs/TOKENOMICS.md) for full details and current testnet addresses.

---

## Tokenomics & Deflationary Pressure

Three continuous deflationary forces will compress circulating PLX over time:

1. **Quarterly buyback-and-burn**: a portion of launchpad revenue is used to buy PLX from the open market and permanently burn it.
2. **Direct fee burn**: PLX paid for premium services can be burned at the contract level rather than recycled.
3. **Staking lock-up**: PLX staked for governance and revenue share is removed from circulation while locked.

As the TON ecosystem grows and our launchpad customer base expands, demand for PLX increases while supply contracts. The team allocation (10%) is locked in the on-chain `TeamVesting` contract that releases tokens linearly over 180 days from launch — meaning the team cannot sell tokens during the first six months of trading, regardless of any party's intent.

---

## Security, Trust & Verifiability

The entire codebase is open-source under the **MIT** license, with **60+ automated tests** covering minter operations, per-holder wallet behavior, vesting schedules, governance transitions, and bounce-message handling on edge cases. Continuous integration runs on every commit and pull request, and the full test suite must pass before code can land on `master`. Each contract is built deterministically and source-verified on Tonviewer immediately after deployment.

A formal third-party audit by a reputable firm is scheduled for **Q1 2027** — funded by launchpad revenue rather than venture capital. This timing is intentional: our incentives as the audit's commissioner align with users and protocol stability rather than with investors who might pressure for a faster, lower-quality review. Until the formal audit lands, the security stance rests on three pillars anyone can verify today: comprehensive test coverage, public source code, and on-chain transparency for every state change.

The contract suite has also been internally reviewed against three known TON Jetton failure modes — bounce-message handling, gas-management dust accumulation, and cell-padding/serialization — with all findings documented and remediated in [`SECURITY.md`](SECURITY.md). The mainnet release will ship with `TeamVesting` v1.1, which adds a bounce-rollback handler and an admin-only TON dust withdrawal.

---

## Treasury Policy

The Treasury wallet holds 25% of supply (250,000,000 PLX) and its address is published in our transparency document. The Treasury allocation is exclusively for ecosystem development: seeding initial liquidity on TON DEXes (Ston.fi, DeDust), funding partner integrations, executing the buyback-and-burn program, and supporting open-source contributors. Every Treasury movement — every transfer, every burn, every payment — is verifiable on-chain in real time. Starting the quarter after mainnet launch, Phalanx Foundation will publish **quarterly transparency reports** detailing inflows, outflows, remaining balance, and rationale for each significant movement. The Treasury is not a black box; it is a public utility.

---

## Governance & Path to Decentralization

Phalanx Foundation operates under a **pseudonymous-but-accountable** model: contributors' personal identities are not published, but every on-chain action, every code commit, and every Treasury movement is permanently recorded and verifiable on TON and GitHub. This approach prioritizes the security and operational independence of contributors while still giving the community complete cryptographic verification of all Foundation activity.

Our explicit goal is to evolve into a fully community-owned foundation — where PLX holders directly govern protocol decisions through on-chain voting. This will start with non-binding signaling in Q3 2026, and progress to binding governance over Treasury allocations, contract templates, and protocol parameters in Q4 2026. The path to decentralization is itself open: every governance milestone will be a public commit, and the contracts that enable voting will be open-sourced and audited alongside the existing primitives.

---

## Roadmap

- **Q2 2026** — Mainnet launch of PLX, full open-source release of the contract library, and public documentation.
- **Q3 2026** — Tokenization Toolkit MVP launches with three pilot deployments (free for early projects in exchange for testimonials and feedback), followed by initial integrations with TON wallets and DEX aggregators.
- **Q4 2026** — Toolkit reaches general availability with native PLX payment integration; the initial governance module ships; and the developer SDK lets third-party applications embed PLX-powered functionality.
- **Q1 2027** — Multi-chain feasibility study begins, evaluating Solana and EVM-compatible chains for expansion; the formal third-party security audit completes and is published.
- **Q2 2027 and beyond** — Cross-chain bridge integration, Foundation-funded grants for community-built primitives, and continuous expansion of the contract template library based on community votes.

Each milestone is a public commitment. If a milestone slips, the slip will be transparent and explained on GitHub.

---

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

---

## Repository Structure

```
plx-token/
├── contracts/              # Tolk source contracts
│   ├── JettonMinter.tolk   # TEP-74 minter (mintable, owner-transferable, burnable via wallet)
│   ├── JettonWallet.tolk   # TEP-74 per-holder wallet
│   ├── TeamVesting.tolk    # Linear vesting (6 months) for team allocation; v1.1 bounce-safe
│   ├── messages.tolk       # TLB message structs (opcodes)
│   ├── storage.tolk        # Contract storage layouts
│   ├── errors.tolk         # Error code enum
│   ├── fees-management.tolk # Gas/storage fee math
│   ├── jetton-utils.tolk   # Wallet address derivation
│   └── sharding.tolk       # Workchain & shard constants
├── tests/                  # Native Tolk tests (60+ passing)
├── scripts/                # Deployment & operational scripts
├── wrappers/               # Auto-generated TS-style wrappers
├── metadata/               # On-chain metadata (logo, JSON)
├── docs/                   # TOKENOMICS, DEPLOYMENT, etc.
└── Acton.toml              # Project manifest
```

---

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
acton test            # run 60+ tests
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

---

## Differentiation & Long-Term Defensibility

The TON ecosystem currently lacks a professional, audited tokenomics-as-a-service offering. Most projects launch tokens by forking unmaintained reference code, modifying it without formal review, and deploying by hand — a pattern that has caused real losses on other chains. Phalanx Foundation enters this gap as a **first mover** with three durable advantages: a contract library that is deeply tested on testnet (60+ tests passing), a foundation operating model designed for long-term independence rather than quick exits, and a token economy where revenue flows back to holders through buyback-and-burn instead of diluting them. These are not promises; they are mechanisms encoded in smart contracts that anyone can verify.

---

## Risk Disclosure

Phalanx Foundation does not promise any specific price, return, or yield, and does not market PLX as an investment product. Our commitments are to ship verifiable on-chain infrastructure, to maintain an open Treasury, and to permanently lock supply through public deployment events. The principal risks to understand are: **adoption risk** — the launchpad must attract real customers, and like any service business, demand is not guaranteed; **ecosystem dependency** — early growth correlates with the TON ecosystem itself, partly mitigated by our multi-chain expansion path; and **regulatory variation** — utility token classification differs across jurisdictions, and participants must evaluate their local law independently. We disclose these not as a formality, but because the alignment between team and community begins with honesty. Anyone evaluating PLX should do so on the basis of verifiable code, disclosed tokenomics, and their own independent assessment of execution risk — not marketing claims.

---

## Documentation

- [Tokenomics](docs/TOKENOMICS.md) — distribution, vesting schedule, treasury policy
- [Transparency](docs/TRANSPARENCY.md) — wallet registry, movement policy, audit trail
- [Deployment](docs/DEPLOYMENT.md) — testnet/mainnet step-by-step
- [Architecture](docs/ARCHITECTURE.md) — contract design and message flows
- [Mainnet Checklist](docs/MAINNET-CHECKLIST.md) — production deploy gates
- [Testnet Deployment Record](docs/TESTNET-DEPLOYMENT-RECORD.md) — live testnet evidence
- [Security Policy](SECURITY.md) — vulnerability reporting and internal review log
- [Contributing](CONTRIBUTING.md) — guide for outside contributors

---

## Join

The fastest way to evaluate Phalanx is to read the code yourself. Every contract lives at [github.com/phalanx-foundation/plx-token](https://github.com/phalanx-foundation/plx-token). Every test reproduces on your machine in under five minutes. Every token movement verifies on Tonviewer. Open a pull request, file a discussion, ask a question. Phalanx is open by design — many shields, one formation, one direction.

## Built By

The **Phalanx Foundation** team. Find us on [GitHub](https://github.com/phalanx-foundation).

## License

MIT — see [LICENSE](LICENSE).
