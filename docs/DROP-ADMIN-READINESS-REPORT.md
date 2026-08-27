# PLX Drop Admin Readiness Report

> **Audit date:** 2026-08-26 (UTC+7)  
> **Completion update:** 2026-08-27 (UTC+7)  
> **Auditor:** Cursor Agent (holistic plan execution)  
> **Minter (EQ):** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`  
> **Decision:** **DONE — admin DROPPED / REVOKED** — supply fixed forever (`mintable: false`, admin null).

---

## Executive summary

| Question | Answer |
|----------|--------|
| Which wallet signed drop admin? | **PLX Deployer (W5)** `EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj` |
| What is “PLX Minter” watch-only? | **Jetton master contract** — target of tx, not signer |
| What is “Team Minter” watch-only? | **TeamVesting contract** — rename label to “Team Vesting” |
| Is supply fully distributed? | **Yes** — 1B PLX minted; LP wallet seeded to Ston.fi DEX |
| Admin status (live)? | **Dropped / revoked** — TonAPI & `/api/plx-stats`: `mintable: false`, `adminAddress: null` |

---

## Live verification (post-drop)

| Check | Expected | Result |
|-------|----------|--------|
| `mintable` | `false` | **PASS** |
| Admin address | null / absent | **PASS** |
| Total supply | 1B PLX | **PASS** |
| Dashboard Mint / Drop Admin panels | Hidden | **PASS** |

Verify:
```bash
curl -s "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
curl -s "https://plx.foundation/api/plx-stats?minter=EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS&network=mainnet"
```

> Sections below retain the **pre-drop audit trail** from 2026-08-26 for history. Status lines that said NO-GO / mintable true are superseded by this completion update.

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
| `mintable` | `true` (pre-drop audit) → **`false` (live)** | — | **Admin dropped** |
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

### Repo CI (`contracts.yml`) — **PASS locally 2026-08-26** (push pending GPG)

Previously FAIL (2026-08-25) on toolkit templates:

- `LiquidityLocker.tolk` — missing `jetton-utils` + wrong unlock body → **fixed** (`AskToTransfer` to own LP jetton wallet)
- `TokenGovernance.tolk` — invalid method / map / `Cell` types → **fixed**

Verified on Ubuntu (`acton build` + `acton test`): **130 passed in 19 files**.

| Contract family | Blocks drop admin? | Reason |
|-----------------|-------------------|--------|
| `JettonMinter` / `JettonWallet` (PLX live) | **No** | Already deployed & unchanged |
| `LiquidityLocker`, `TokenGovernance` | **No** for drop — templates now compile | Not deployed as PLX genesis |
| Future toolkit features (airdrop, staking, NFT, games) | **No** | New deploy per customer / off-chain API |

**Conclusion:** No need for `UpgradeMinterCode` on PLX genesis before drop. Gate C1 (green tests) is **satisfied locally**; commit/push when GPG signing is available so GitHub Actions mirrors this.

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
| B3 | ton-assets PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) | **CLOSED tanpa merge** — reviewer Tonkeeper (2026-06-05): *“no Scam label right now… develop your token… return if you will develop it in the future.”* Artinya PR ditolak/ditutup, **bukan** masuk ke daftar resmi ton-assets. Buka PR baru nanti setelah produk lebih mature. Soft gate untuk drop (TonAPI sudah `whitelist`). |
| B4 | Deployer mnemonic backup | **Perlu konfirmasi Anda** — lihat penjelasan “backup PLX Deployer” di bawah |

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
| C1 `acton test` green | **PASS lokal** (130 tests; push GPG pending) | Soft until GitHub green |
| C2 Deploy log on server | **NOT CHECKED** (no SSH this audit) | — |
| C3 Drop admin decision | **DONE — admin dropped / revoked** | — |
| Prod API `/health/db` | **PASS** | — |
| Toolkit Fase 1 E2E | **OPEN** | Recommended before irreversible step |
| Metadata final | **ACCEPTED short** or update before drop | Optional |

### **Final decision: DONE — admin DROPPED / REVOKED**

Drop admin **sudah dieksekusi** (2026-08). Live checks: `mintable: false`, admin null. Mint + Drop Admin panels di dashboard PLX disembunyikan.

---

## 8. Apa arti “CLOSED, not merged”?

Di GitHub, sebuah Pull Request punya dua jalur akhir:

| Status | Arti |
|--------|------|
| **Merged** | Perubahan **diterima** dan masuk ke branch utama repo target |
| **Closed (tanpa merged)** | PR **ditutup ditolak / dibatalkan** — kode **tidak** masuk |

PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) ke `tonkeeper/ton-assets` = **closed tanpa merge**. Tim Tonkeeper menutupnya dengan komentar: label SCAM sudah tidak ada saat itu, dan mereka minta proyek “dikembangkan dulu” sebelum verifikasi resmi. Itu **bukan** kegagalan teknis kontrak PLX; itu penundaan listing di registry Tonkeeper. Re-submit PR baru nanti. Sementara TonAPI sudah `whitelist`.

---

## 9. Apa itu “backup PLX Deployer”?

**PLX Deployer** (`EQBfYLpq…` / Tonkeeper `UQBfYLpq…anhSm`) adalah wallet yang:

- punya **seed phrase / mnemonic 24 kata** (disimpan di server sebagai `plx-deployer-v2` di `wallets.toml`)
- **sebelum drop** adalah admin minter PLX; **setelah drop** tidak lagi punya mint authority
- historis: satu-satunya yang bisa sign `DropMinterAdmin`, `ChangeMinterMetadata`, atau `UpgradeMinterCode` (mint/admin ops sudah tidak tersedia setelah drop)

**Backup** berarti: Anda (operator) punya salinan mnemonic itu di tempat aman **offline** (paper / hardware wallet / encrypted vault), **terpisah** dari laptop yang bisa rusak, dan Anda sudah pernah **uji restore** (bisa buka wallet yang sama di Tonkeeper dari seed). Tanpa backup, jika server `wallets.toml` hilang sebelum/saat drop, Anda bisa kehilangan kontrol admin **sebelum** drop selesai — atau tidak bisa menyelesaikan transaksi darurat.

Ini **bukan** backup alamat watch-only “PLX Minter” (itu kontrak, tidak punya seed).

---

## 10. Drop execution guide (when GO)

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

## 11. What drop admin does NOT block

Toolkit continues to deploy **new** contracts (jetton, NFT, airdrop, staking templates), operate Scratch (`/game/scratch/*`), PaymentSplitter rail, analytics API, and custom client deploys. Only **PLX genesis minter** admin powers are removed permanently.

---

*Updated 2026-08-27: admin drop **completed** (`mintable: false`, admin revoked). Pre-drop NO-GO narrative kept above for audit history only.*
