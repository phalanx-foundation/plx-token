# Phalanx (PLX) — Treasury Transparency Report

> Phalanx Foundation is committed to full on-chain transparency. This document
> publishes all treasury and operational wallet addresses with their purpose,
> governance, and movement policy. All movements are auditable on Tonviewer.

## Public Wallet Registry

> **Note:** internal nicknames in operational tooling differ from public labels.
> The on-chain address is the only canonical identifier. Public labels here
> are what we ask blockchain explorers (Tonviewer, Tonscan) to display.

### Testnet (live, demonstrative)

| Public Label | Address | Allocation | Purpose | On-chain Lock |
|---|---|---:|---|---|
| **Phalanx Foundation — Liquidity Reserve** | `kQD4-ER4sDGmw4PcPPJ-AwLYG9TORvZ5sJ-xNKthunKz0AOP` | 400M PLX (40%) | DEX liquidity provisioning (Ston.fi / DeDust) | Will lock LP tokens 12 months post-launch |
| **Phalanx Foundation — Treasury** | `kQCAfIuFFlS8RJyYQU7pFaN1XqcO8V4lZl-SH8Ca950XqGal` | 250M PLX (25%) | Operations, buyback & burn, strategic grants | Multi-sig on roadmap |
| **Phalanx Foundation — Community Treasury** | `kQAZWyvZBkUctnlbqP8EVTzh43g7JcYod9NqYjenRbf2nPiC` | 200M PLX (20%) | Airdrops, contests, partner integrations | Releases governed by community proposals |
| **Phalanx Foundation — Team Vesting (6mo linear)** | `kQDNPoiPbKXwjt4i9SqtBmvbUlMgWz1jCR7M5Uwjj5fI8t1l` | 100M PLX (10%) | Team allocation under on-chain vesting contract | **180-day linear release** — enforced by smart contract |
| **Phalanx Foundation — Marketing** | `kQD51illBEG2sQ5do-28UoVDyiQbyRMVagzfwnWV7QCginMA` | 50M PLX (5%) | Listing fees, content, partnerships | Spend reports published quarterly |
| **Phalanx Foundation — Deployer (active)** | `kQBg9RFEVaQIh3xVonBxCnIb2Vw19y-rSD4uO1LR0eNH4zT2` | 0 PLX | Contract deployment & admin operations only. **Will renounce minter admin 7 days after mainnet launch.** | — |
| **Phalanx Foundation — Deployer (retired, drill)** | `kQB1GGwuoPV1vS2DjEg-weTPy5_HQU4ipqQm6KO05EyqEizN` | 0 PLX | Retired during 2026-05-20 rotation drill. No longer holds admin authority. Testnet only. | retired |

### Mainnet

To be published after mainnet deployment. Contract addresses are deterministic
from initial config; you can verify them ahead of time using `acton script
info-distribution`.

## Movement Policy

To prevent market shock and uphold trust:

1. **Treasury sales**: Phalanx Foundation does **not sell directly to retail**.
   Treasury operations (buyback & burn, partnerships) are pre-announced 48h in
   advance on Twitter and Telegram, and visible on-chain.

2. **Community rewards**: distributions from the community treasury are
   announced via signed proposals (Twitter + Telegram). Recipients are
   verifiable on-chain.

3. **Team vesting**: 100M PLX team allocation is **smart-contract enforced**.
   Beneficiary cannot withdraw more than the linearly-vested amount. After 6
   months, full allocation unlocks. View live unlock progress with:
   ```
   acton script vesting-status
   ```

4. **Marketing wallet**: each spend (listing fee, sponsored content) will be
   accompanied by an on-chain memo and reported in the quarterly transparency
   update.

5. **No private sale, no presale, no pre-mine to insiders.** Initial
   distribution went only to the addresses listed above. There is no
   undocumented allocation.

## Verification Steps for Investors

Anyone can verify our claims independently:

1. **Open Tonviewer** for the Jetton Minter:
   - Testnet: https://testnet.tonviewer.com/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV
   - Mainnet: (TBD)

2. **Check Total Supply** — should be exactly 1,000,000,000 PLX (1e18 nano)

3. **Check Holders distribution** — top 5 should match the public registry above

4. **Verify the vesting contract code** — source is open at
   `contracts/TeamVesting.tolk` in this repo. Build with `acton build
   TeamVesting` and compare cell hash on-chain.

5. **Track `JettonMinter` admin field** — after the 7-day post-launch
   stabilization, admin will be set to `addr_none` (zero), making supply
   permanently fixed.

## Submitting Address Labels to Explorers

After mainnet deploy, Phalanx Foundation will submit verified label requests to:

- [ ] **Tonviewer** — https://tonviewer.com/contact (request "Phalanx Treasury",
      "Phalanx LP Reserve", etc. labels)
- [ ] **Tonscan** — https://tonscan.org/labels (community-verified labels)
- [ ] **Tonkeeper jetton list** — PR to https://github.com/tonkeeper/ton-assets
      with metadata, social links, description

Once approved, our wallet addresses will display the verified label badge in
all third-party tools.

## Audits & Reviews

- **Internal:** all 60 unit tests pass (`acton test`)
- **Testnet validation:** full distribution + claim flow verified end-to-end
  (see `TESTNET-DEPLOYMENT-RECORD.md`)
- **Code:** open source, MIT-style license, available at
  https://github.com/phalanx-foundation/plx-token

External third-party audit budget: planned for Q4 2026 once volume justifies
the cost (~$5K-$15K from third-party auditor). Will be funded from treasury.

## Contact

- **Issues / public questions:** https://github.com/phalanx-foundation/plx-token/issues
- **Security disclosures:** see `SECURITY.md` for the responsible-disclosure process

---

*Last updated: 2026-05-20 — Phalanx Foundation.*
