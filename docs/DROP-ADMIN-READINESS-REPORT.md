# PLX Drop Admin Readiness Report

> **Audit date:** 2026-08-26 (UTC+7)  
> **Auditor:** Cursor Agent (holistic plan execution)  
> **Minter (EQ):** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`  
> **Decision:** **NO-GO** — do not drop admin until gates below are resolved or explicitly waived in writing.

---

## Executive summary

| Question | Answer |
|----------|--------|
| Which wallet signs drop admin? | **PLX Deployer (W5)** `EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj` |
| What is “PLX Minter” watch-only? | **Jetton master contract** — target of tx, not signer |
| What is “Team Minter” watch-only? | **TeamVesting contract** — rename label to “Team Vesting” |
| Is supply fully distributed? | **Yes** — 1B PLX minted; LP wallet ~96.5k PLX seeded to Ston.fi DEX |
| Safe to drop admin today? | **No** — CI red on repo, ton-assets PR not merged, metadata/ecosystem narrative gap, Fase 1 toolkit gates open |

---

## 1. Tonkeeper address verification (Fase 0)

All three user addresses decode to the **same raw account** as canonical EQ docs ([`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md)).

| Label | User (UQ) | Canonical (EQ) | Raw hash (TonAPI) | Match |
|-------|-----------|----------------|-------------------|-------|
| PLX Minter | `UQCbaUJqi…EDGE5nVa8X` | `EQCbaUJqi…EDGE5nVfLS` | `0:9b69426a…e6755` | **PASS** — suffix `nVa8X` vs `nVfLS` is UQ vs EQ encoding |
| Team Vesting | `UQCs-Y2wb…lsGOg` | `EQCs-Y2wb…lsD5l` | `0:acf98db0…ea5b0` | **PASS** |
| PLX Deployer | `UQBfYLpq…anhSm` | `EQBfYLpq…anklj` | `0:5f60ba6a…d1a9e` | **PASS** |

**On-chain admin** = deployer raw `0:5f60ba6a44da788d5bdf7d86fab9c91c1953364b917527ca6afa99c5b0dd1a9e` — **matches PLX Deployer**.

---

## 2. On-chain audit (Fase 1)

### Jetton master

| Field | Live value | Gate | Result |
|-------|------------|------|--------|
| `total_supply` | 1,000,000,000 PLX (9 decimals) | A1 | **PASS** |
| `mintable` | `true` | — | Admin not dropped yet |
| `admin` | PLX Deployer | — | Expected |
| TonAPI `verification` | `whitelist` | B1 | **PASS** |
| Metadata `image` | `https://plx.foundation/plx-logo.png` | A4 (HTTP 200) | **PASS** |
| Metadata `description` | Utility + toolkit payment rail (short) | — | See §5 |

### Holder balances vs docs

| Role | Expected PLX | On-chain PLX | Result | Notes |
|------|-------------:|-------------:|--------|-------|
| LP wallet | 400,000,000 | 399,903,500 | **WARN** | ~96,500 PLX in Ston.fi DEX pool (LP seeding) |
| Treasury | 250,000,000 | 250,000,000 | **PASS** |
| Community | 200,000,000 | 200,000,000 | **PASS** |
| Team Vesting | 100,000,000 | 100,000,000 | **PASS** |
| Marketing | 50,000,000 | 50,000,000 | **PASS** |
| Deployer | 0 | 0 | **PASS** |
| Ston.fi DEX (pool) | — | 95,530.51 | **INFO** | Named holder on TonAPI |
| Other micro-holders | — | ~970 PLX | **INFO** | Swap dust / quest activity |

**Supply integrity:** Sum of all holders = 1,000,000,000 PLX — **PASS**.

**A2 interpretation:** Genesis allocation intact; LP wallet balance reduced only by disclosed micro-LP seeding into Ston.fi — not a minting anomaly.

### Other mainnet contracts

| Contract | Address | Status |
|----------|---------|--------|
| PaymentSplitter | `EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv` | **active** |
| Team Vesting | `EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l` | **active** |

---

## 3. Contract upgrade matrix (Fase 2)

### PLX genesis minter (`JettonMinter.tolk` v1.0.0 on-chain)

| Check | Result |
|-------|--------|
| `JettonMinter.tolk` / `JettonWallet.tolk` changed since 2026-06 deploy | **No commits** — deployed code matches repo at deploy time |
| Open PR need `UpgradeMinterCode` on PLX genesis | **None identified** |
| NFT getter fix (`NftCollection`, `CompressedNftCollection`) | **Separate contracts** — deploy new collections; no PLX minter upgrade |
| cNFT merkle / claim changes | **Separate contracts** + API — no PLX minter upgrade |

### Repo CI (`contracts.yml`) — **FAIL** (2026-08-25)

Build errors in **toolkit templates**, not PLX genesis minter:

- `LiquidityLocker.tolk` — undefined `jettonEmptyForwardPayload`
- `TokenGovernance.tolk` — invalid `self` parameter position

| Contract family | Blocks drop admin? | Reason |
|-----------------|-------------------|--------|
| `JettonMinter` / `JettonWallet` (PLX live) | **No** — if no on-chain bug found | Already deployed & unchanged |
| `LiquidityLocker`, `TokenGovernance` | **No** for drop — **Yes** for toolkit template quality | Not deployed as PLX genesis |
| Future toolkit features (airdrop, staking, NFT, games) | **No** | New deploy per customer / off-chain API |

**Conclusion:** No evidence that PLX genesis minter **requires** `UpgradeMinterCode` before drop. CI failure is a **process gate** (C1 in [`MAINNET-GO-NO-GO.md`](MAINNET-GO-NO-GO.md)) — fix templates + green tests before calling ops “final”.

---

## 4. Production smoke (Fase 3)

| Check | URL / route | Result |
|-------|-------------|--------|
| API DB | `GET /health/db` | **PASS** — `db: connected` |
| API deploy mode | `GET /health/deploy` | **PASS** — `broadcast`, `mainnet_enabled: true` |
| PLX stats | `GET /public/plx-stats` | **PASS** — price, 9 holders, 1B supply |
| Scratch game | `GET /game/scratch/health` | **PASS** — `enabled: true`, vaults OK |
| PaymentSplitter on-chain | TonAPI account | **PASS** — active |
| PLX payment quote | `POST /payments/plx/quote` | **401** — auth required (expected) |
| Web signin | `https://plx.foundation/auth/signin` | **200** |
| Web pricing | `/pricing` | **200** |
| Web build | `/build` | **200** |
| Web plx-token | `/plx-token` | **200** |
| Web dashboard | `/dashboard` | **200** |
| Logo HTTPS | `https://plx.foundation/plx-logo.png` | **200** |
| Drop admin UI | `web/components/dashboard/drop-admin-panel.tsx` | **Present in repo** (commit `53f7023f`); SSR HTML does not embed strings (client-rendered) |

### Toolkit Fase 1 gates ([`POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md`](POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md))

| Gate | Status |
|------|--------|
| Auth E2E production-ready | **OPEN** — not fully verified this audit |
| `/build` happy path E2E | **OPEN** |
| Single documented happy-path runbook | **PARTIAL** |

---

## 5. Metadata decision (Fase 4)

### Three sources compared

| Source | Description summary |
|--------|---------------------|
| **On-chain (live)** | Utility token; audited Jetton minter, team vesting, Tokenization Toolkit payment rail |
| [`metadata/phalanx-metadata.json`](metadata/phalanx-metadata.json) | Developer tools, services, on-chain products on TON |
| [`metadata/ton-assets-PLX.yaml`](metadata/ton-assets-PLX.yaml) | Similar short text + websites/social |

### Gaps vs product narrative

Not mentioned on-chain today: Scratch Seeker, Midas Hand / launchpad, NFT/cNFT/SBT templates, dashboard analytics integration, games roadmap, staking/governance hooks.

### Recommendation

| Option | When | Action |
|--------|------|--------|
| **A — Update before drop** | Want explorer/wallet description to reflect full toolkit + games | `ChangeMinterMetadata` signed by **PLX Deployer** (~0.05 TON gas); draft text ≤ ~500 chars; then re-audit TonAPI cache |
| **B — Accept current (recommended short-term)** | TonAPI already `whitelist`; narrative lives on plx.foundation / whitepaper | Drop admin later without metadata change; ton-assets YAML carries extended fields when PR re-opened |

**Decision for this audit:** **Option B accepted for drop timing** — but **metadata update is still available until drop** if marketing wants Option A first.

**Note:** `ton-assets-PLX.yaml` raw address field differs from live minter raw — verify before re-submitting PR #5468.

---

## 6. Registry & Tonkeeper (Gate B)

| # | Check | Result |
|---|-------|--------|
| B1 | TonAPI verification `whitelist` | **PASS** |
| B2 | Tonkeeper device — no SCAM label | **NOT VERIFIED** (requires physical device) |
| B3 | ton-assets PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) | **FAIL** — `CLOSED`, **not merged** |
| B4 | Deployer mnemonic backup | **ASSUMED** — operator must confirm vault offline |

---

## 7. GO / NO-GO checklist

| Gate | Status | Blocker? |
|------|--------|----------|
| A1 Supply 1B | **PASS** | — |
| A2 Distribution | **PASS** (with LP seeding WARN) | — |
| A3 Deployer 0 PLX | **PASS** | — |
| A4 Logo HTTPS | **PASS** | — |
| B1 TonAPI whitelist | **PASS** | — |
| B2 Tonkeeper SCAM | **UNKNOWN** | Soft — whitelist may suffice |
| B3 ton-assets merged | **FAIL** | Soft for drop — hard for announce |
| B4 Wallet backup | **UNCONFIRMED** | Hard for drop execution |
| C1 `acton test` green | **FAIL** | Process / quality gate |
| C2 Deploy log on server | **NOT CHECKED** (no SSH this audit) | — |
| C3 Drop admin decision | **NO-GO documented** | — |
| Prod API `/health/db` | **PASS** | — |
| Toolkit Fase 1 E2E | **OPEN** | Recommended before irreversible step |
| Metadata final | **ACCEPTED short** or update before drop | Optional |

### **Final decision: NO-GO**

Drop admin **deferred**. Irreversible step should run only after:

1. Operator confirms **B4** (deployer mnemonic / `wallets.toml` recovery).
2. **C1** — green CI or written waiver that PLX genesis contracts are isolated from failing templates.
3. Explicit choice on **metadata** (update now vs accept current).
4. User **explicit approval** after reading this report.

---

## 8. Drop execution guide (when GO)

**Signer:** PLX Deployer — **not** PLX Minter watch-only.

| Method | Steps |
|--------|-------|
| Dashboard | Connect PLX Deployer → Token Tools → Fix supply (drop admin) → confirm → TonConnect sign to minter address |
| CLI (Ubuntu) | `PLX_CONFIRM_DROP_ADMIN=1 acton script scripts/drop-admin.tolk --net mainnet` with wallet `plx-deployer-v2` |

**Post-drop verify:**

- TonAPI: `mintable: false`, admin null/absent
- Dashboard: mint + drop panels hidden for PLX deployment
- Tonviewer getters: `get_jetton_data` mintable flag false

---

## 9. What drop admin does NOT block

Toolkit continues to deploy **new** contracts (jetton, NFT, airdrop, staking templates), operate Scratch (`/game/scratch/*`), PaymentSplitter rail, analytics API, and custom client deploys. Only **PLX genesis minter** admin powers are removed permanently.

---

*Generated by holistic drop-admin audit plan. Do not edit [`plx_drop_admin_audit_db651ceb.plan.md`](../../.cursor/plans/) — update this file for subsequent audit runs.*
