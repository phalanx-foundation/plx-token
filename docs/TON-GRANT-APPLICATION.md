# TON Foundation Grant Application — Phalanx (PLX)

> **Status:** Draft - siap di-submit via TON Builders Portal  
> **Dibuat:** 2026-07-10  
> **Target submit:** segera  

---

## Ringkasan Strategi

| Item | Detail |
|------|--------|
| **Portal** | https://builders.ton.org (TON Builders Portal) |
| **Vertikal** | Simplified DeFi + Open-Source Public Goods |
| **Track** | Non-commercial grants (open-source tools & infrastructure) |
| **Tier target** | Contender → Champion (upgrade setelah traction) |
| **Ask** | 50-100 TON untuk LP bootstrap + 1 third-party audit |
| **Timeline** | Immediate (project sudah live mainnet) |

---

## Kenapa PLX Cocok untuk TON Foundation Grant

### A. Simplified DeFi — "No-code Token Toolkit for TON"

PLX adalah **launchpad tanpa kode** untuk deploy TON Jetton. Setiap project bisa deploy token dengan:
- Vesting on-chain (TeamVesting — linear 180 hari)
- Multisig admin opsional
- Governance hooks (TokenGovernance DAO)
- Anti-whale protection
- Staking + Lock Vault langsung

Ini menyederhanakan DeFi di TON: **dari butuh developer 2-3 bulan → cukup 5 menit di browser.**

### B. Open-Source Public Goods (22 kontrak, MIT)

Semua kontrak PLX open-source MIT — bisa dipakai **project TON manapun** dengan tokennya masing-masing:

- `TokenStaking` — generic, terima jetton TEP-74 apapun
- `TokenLockVault` — 16 tier locking, bonus rewards
- `TokenGovernance` — DAO voting + timelock
- `LiquidityLocker` — anti-rug LP locker
- `PaymentSplitter` — 50% burn + 50% treasury, on-chain

### C. Self-funded, no VC — aligned with TON independence

PLX tidak punya VC, tidak ada token sale, tidak ada IDO. Murni dibangun dari resource sendiri. Grant TON akan langsung ke **LP publik** (transparan, on-chain, verifiable).

---

## Aplikasi Draft — TON Builders Portal

### 1. Project Name

**Phalanx (PLX)** — No-Code Tokenization Toolkit for TON

### 2. One-liner (Elevator Pitch)

> Phalanx lets any project deploy a fully-audited TON Jetton with on-chain vesting, staking, governance, and anti-whale protection — in 5 minutes, from a browser, no code required. 22 MIT-licensed smart contracts, already live on TON mainnet.

### 3. Website & Links

| Link | URL |
|------|-----|
| Web Toolkit | https://plx.foundation |
| Mini App | https://app.plx.foundation |
| Admin | https://dev.plx.foundation |
| GitHub (public) | https://github.com/phalanx-foundation/plx-token |
| Docs | https://github.com/phalanx-foundation/plx-token/tree/master/docs |
| Bot | @phalanxfoundationbot |

### 4. Vertical

**Primary:** Simplified DeFi  
**Secondary:** Telegram In-App Economy (Mini App + Bot)

### 5. Stage

**Grow** — Mainnet live, toolkit MVP, seeking LP bootstrap & audit

### 6. Problem We Solve

TON has 174M+ smart contracts but deploying a Jetton with professional-grade features (vesting, anti-whale, staking, governance) requires:
- 2-3 months of Solidity/Tolk development
- Security audit ($15K-$50K)
- Testing across multiple wallet standards

This blocks adoption — only well-funded projects can launch professionally.

**Phalanx solves this:** Browser-based wizard → configure metadata → pay → sign with Tonkeeper → Jetton deployed in 5 minutes. All contracts pre-audited, all features battle-tested.

### 7. Product / What We've Built

**Smart Contract Library (22 contracts, all MIT):**

| Category | Contracts | Status |
|----------|-----------|--------|
| Core Jetton | Minter, Wallet, messages, storage, errors | Mainnet LIVE |
| Vesting | TeamVesting (linear 180-day, bounce-safe) | Mainnet LIVE |
| Payments | PaymentSplitter (50% burn, 50% treasury) | Mainnet LIVE |
| Staking | TokenStaking (APR accrual, generic) | Testnet ready |
| Lock Vault | TokenLockVault (16 tiers, bonus rewards) | Testnet ready |
| Governance | TokenGovernance (DAO, quorum, timelock) | Testnet ready |
| LP Locker | LiquidityLocker (anti-rug timelock) | Testnet ready |
| Anti-Whale | AntiWhaleJettonWallet | Ready |
| Fee Token | FeeJettonMinter/Wallet | Ready |
| Airdrop | PlxAirdrop | Ready |

**Toolkit Wizard (Web):**
- Browser-based, no-code flow
- TON Connect + Tonkeeper integration
- 6 Jetton templates: standard, antiwhale, fee, mintable, staking, airdrop
- Payment rails: TON, PLX (50% discount), PayPal
- Pricing: https://plx.foundation/pricing

**Telegram Integration:**
- Mini App at app.plx.foundation (TON Connect, Telegram SDK, analytics)
- Bot @phalanxfoundationbot (/start, /quest, /swap, /price, /site)

**Infrastructure:**
- All Cloudflare-native: Workers (SSR), Pages (admin), Containers (API)
- Neon PostgreSQL for user data
- TON Console project with TonAPI key

### 8. TON Ecosystem Integrations

| Integration | Status |
|-------------|--------|
| TEP-74 Jetton (standard) | Mainnet deployed |
| TEP-89 On-chain Metadata | Active |
| Tonkeeper Verification | **whitelist** (PR #5540, merged 2026-06-15) |
| TON Connect | Active (wizard + mini app) |
| TonAPI | Active (TON Console) |
| Ston.fi DEX | PLX/TON pool live |
| Tonviewer / Tonscan | Contracts verified |
| Telegram WebApp SDK | Integrated |
| Telegram Bot API | @phalanxfoundationbot |
| Cloudflare Workers/Pages/Containers | All production infra |
| tApps Center | Checklist ready, pending submission |
| Tonkeeper USD Display | Pending (need >= 100 TON LP + >= 100 holders) |

### 9. Traction (Current)

| Metric | Value |
|--------|-------|
| On-chain holders | 9 (5 distribution wallets + vesting + LP + toolkit) |
| Ston.fi LP | ~9.75 TON + ~95,929 PLX (~$34) |
| Smart contracts | 22 (all compiled, tested) |
| Automated tests | 72 passing (7 test files) |
| Toolkit pricing tiers | 3 tiers (Free, Standard 20 TON, Pro) |
| Bot commands | 5 active |

**Current blocker:** Thin liquidity ($34 TVL) prevents price discovery, Tonkeeper USD display, and CoinGecko listing.

### 10. What We're Asking For

**Primary: LP Bootstrap Grant**

| Use | Amount | Purpose |
|-----|--------|---------|
| LP seeding (Ston.fi PLX/TON) | 50-80 TON | Boost pool to $3K-$5K (with matching PLX from treasury) |
| Smart contract audit | 20 TON | Third-party audit of TokenStaking + TokenGovernance (CertiK/Trail of Bits level) |

**Total Ask: 70-100 TON** (equivalent ~$115-$164 at current GRAM price)

**Secondary (if Champion tier):** Traffic support + user incentives for toolkit adoption campaign.

### 11. Milestones & Deliverables

| Milestone | Timeline | Deliverable | Verification |
|-----------|----------|-------------|--------------|
| **M1: LP Deepening** | Week 1-2 | Deploy grant TON + matching PLX to Ston.fi pool | On-chain TX + DexScreener |
| **M2: Tonkeeper USD** | Week 2-4 | Hit 100 TON LP + 100 holders gate | Tonkeeper displays PLX price |
| **M3: Mainnet Contracts** | Week 3-6 | Deploy TokenStaking + TokenGovernance + LockVault to mainnet | On-chain contract addresses |
| **M4: Security Audit** | Month 2-3 | Complete third-party audit of new contracts | Published audit report |
| **M5: Toolkit Launch** | Month 3-4 | Full toolkit E2E with all 6 templates | Live deploys via plx.foundation/build |
| **M6: CoinGecko Listing** | Month 4-6 | Hit listing requirements (volume, LP, holders) | CMC/CG page live |

### 12. Team

**Phalanx Foundation** — pseudonymous but accountable, open-source collective.

- **Ony** — Lead Architect (contracts, tokenomics, toolkit)
- Acton CLI expert, Tolk developer
- Wallet: W5 (v5r1) standard
- All commits GPG-signed
- Contact: ops@plx.foundation

### 13. Competitors & Differentiation

| Tool | What They Do | PLX Advantage |
|------|-------------|---------------|
| TonMinter | Basic Jetton deploy | PLX includes vesting, staking, governance, anti-whale — 22 contracts vs 2 |
| DeDust/Ston.fi | DEX (LP only) | PLX covers full lifecycle: create → vest → stake → govern → lock LP |
| Custom dev | Hire Solidity dev | PLX = 5 minutes from browser, audited contracts included |

**No direct competitor offers an end-to-end, no-code Jetton lifecycle suite on TON.**

### 14. Long-Term Vision

**Phase 1 (Now):** LP bootstrap + audit → toolkit live → organic revenue from deploy fees

**Phase 2 (Q4 2026):** DAO governance live → community votes on treasury allocation, fee structure, and new templates

**Phase 3 (2027):** Multi-chain expansion (Solana, EVM) using PLX as cross-chain governance token; token buyback from toolkit revenue deepens LP perpetually

**Phase 4:** Become the standard Jetton deployment suite for TON — every new project deploys token through Phalanx

### 15. Why TON Foundation Should Support This

1. **Lowers barrier to entry** — Any Telegram user/builder can launch a professional-grade Jetton in 5 minutes, no developer needed
2. **Open-source public good** — All 22 contracts are MIT-licensed, reusable by any TON project
3. **Self-funded, no VC extraction** — Grant goes directly to on-chain LP (verifiable, transparent)
4. **TON-native** — Built with official toolchain (Acton + Tolk), TON Connect, TEP standards
5. **Ecosystem multiplier** — Each toolkit deploy creates a new Jetton project → more TON activity, more holders, more DEX volume
6. **Already live** — Not a whitepaper project; contracts deployed, website live, Tonkeeper whitelisted

### 16. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Grant TON dumped | LP deployed on-chain with timelock via LiquidityLocker |
| Audit funds misused | Paid directly to auditor (not to team wallet) |
| Project abandoned | All contracts open-source MIT — ecosystem can fork |
| Low toolkit adoption | Free testnet tier + Telegram quests + Formation Seasons |

---

## Cara Submit

### Step 1: Register di TON Builders Portal

1. Buka **https://builders.ton.org**
2. Connect wallet TON (Tonkeeper)
3. Isi project registration:
   - **Name:** Phalanx (PLX)
   - **Category:** Simplified DeFi / Infrastructure
   - **Stage:** Live on Mainnet
   - **Links:** (copy dari section "Website & Links" di atas)

### Step 2: Pilih Support Program

Setelah register, portal akan menampilkan program yang tersedia:
- **Non-commercial grants** — untuk open-source tools (PLX paling cocok di sini)
- **Champion Grants** — jika project punya traction tinggi

### Step 3: Isi Form Aplikasi

Copy-paste dari section di atas:
1. Project Name → "Phalanx (PLX)"
2. One-liner → (copy section 2)
3. Problem → (copy section 6)
4. Product → (copy section 7)
5. Traction → (copy section 9)
6. Ask → (copy section 10)
7. Milestones → (copy section 11)
8. Team → (copy section 12)
9. Why TON → (copy section 15)

### Step 4: Attach Supporting Materials

- [ ] Link ke GitHub public: https://github.com/phalanx-foundation/plx-token
- [ ] Link ke Tonkeeper PR: https://github.com/tonkeeper/ton-assets/pull/5540
- [ ] Link ke Tonviewer: (contract address explorer)
- [ ] Screenshot toolkit `/build` wizard
- [ ] Test results (72 passing)

### Step 5: Submit & Follow Up

- Portal akan memberi status aplikasi
- Jika tidak ada update dalam 2-4 minggu, follow up via:
  - TON Dev community Telegram/Discord
  - TON events (Gateway, Hack-a-TON)
  - Ecosystem team contacts

---

## Checklist Pra-Submit

- [ ] Toolkit `/build` wizard happy-path E2E complete
- [ ] Screenshot demo `/build` 2-3 menit (video atau GIF)
- [ ] GitHub repo README up-to-date (deskripsikan semua 22 kontrak)
- [ ] Ston.fi pool sudah ada (verifikasi DexScreener)
- [ ] Tonviewer contract verification complete
- [ ] TON Console project registered
- [ ] tApps Center submission checklist ready (bonus points)
- [ ] Tokenomics/Transparency doc published di repo public

---

## Alternatif Parallel Grant

Sambil menunggu review TON Foundation, apply juga ke:

| Grant | Link | Fokus | Amount |
|-------|------|-------|--------|
| **Gitcoin Grants** | https://gitcoin.co | OSS round (matching pool) | ETH matching |
| **TON Accelerator** | (cari via TON events) | Early-stage TON projects | $10K-$50K |
| **Microsoft Founders Hub** | https://foundershub.microsoft.com | Azure credits | Up to $150K credits |
| **Google Cloud Startup** | https://cloud.google.com/startup | GCP credits | Up to $100K credits |

---

*Dokumen ini dipersiapkan untuk submit ke TON Builders Portal. Update setelah submit dengan link aplikasi dan status.*
