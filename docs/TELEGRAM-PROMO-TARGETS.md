# Telegram promo targets — PLX (curated)

Where to **legitimately** promote Phalanx (PLX) — utility jetton + toolkit on TON.  
**Do not** spam random shill groups; follow each community’s rules. Never pay for “guaranteed listing” DMs.

**Canonical links:** [`LISTING-SUBMISSION-PACK.md`](LISTING-SUBMISSION-PACK.md) · Channel: https://t.me/phalanxfoundation

---

## Tier 1 — Official TON / DeFi (highest trust)

| Target | Type | Members* | How to promote | Notes |
|--------|------|----------|----------------|-------|
| [@stonfidex](https://t.me/stonfidex) | Channel | ~200k+ | Pool already live — ask **ambassador / partnership** for spotlight | EN channel; chat: [@stonfichat](https://t.me/stonfichat) |
| [@stonfichat](https://t.me/stonfichat) | Group | ~65k | Share **builder quest** + Ston.fi pool link when rules allow | English only; no raw shill |
| [@stonfiambassadors](https://t.me/stonfiambassadors) | Channel | — | Apply for ambassador cross-post | From STON.fi blog |
| [@dedust](https://t.me/dedust) | Channel | ~80k | After DeDust LP — partnership@dedust.io | Chat: t.me/dedust_en_chat |
| [@toncoin](https://t.me/toncoin) | Channel | ~8M | **No** unsolicited token posts | Ecosystem news only |
| [@toncoin_chat](https://t.me/toncoin_chat) | Group | large | Answer when asked about jettons/tooling; link plx.foundation | Strict moderation |
| [@toncommunitychannel](https://t.me/toncommunitychannel) | Channel | — | Campaigns via **TON Builders Portal** | Was TON Society |
| [@tonchathq](https://t.me/tonchathq) | Group | — | Founder networking after portal registration | TON Fam path |

\*Approximate public counts; verify in Telegram before outreach.

---

## Tier 2 — Builders & infra (fit: toolkit + Tact jetton)

| Target | Type | Angle |
|--------|------|-------|
| [@tactlang](https://t.me/tactlang) | Group | Open-source JettonMinter in Tact/Acton — ask feedback, not “buy” |
| [@tact_kitchen](https://t.me/tact_kitchen) | Channel | Team updates channel — no promo unless invited |
| [@ton_studio](https://t.me/ton_studio) | Channel | TON Studio / Tact ecosystem |
| [TON Builders Portal](https://ton.org/en/ton-ecosystem-support) | Web | Register project → marketing boost, tApps, grants (replaces cold TG DMs) |
| [@tonkeeper](https://t.me/tonkeeper) | Support bot | **Only** ton-assets PR #5540 follow-up — see [`TONKEEPER-TELEGRAM-ESCALATION.md`](TONKEEPER-TELEGRAM-ESCALATION.md) |

---

## Tier 3 — Listings & analytics

| Target | Type | Angle |
|--------|------|-------|
| [DYOR.io](https://dyor.io) + TG list | Product | Already indexed — request card refresh via site |
| [@M3TA_Analytics](https://t.me/M3TA_Analytics) | Channel | TON analytics; pitch after more volume |
| DexScreener | Web | Enhanced profile (paid) — [`DEXSCREENER-PROFILE.md`](DEXSCREENER-PROFILE.md) |

---

## Tier 4 — Launchpads (after deck + demo)

| Target | Type | Risk |
|--------|------|------|
| [@TonUP_io](https://t.me/TonUP_io) | Channel | Launchpad — needs pitch deck |
| [Tonstarter](https://t.me/+RH50YeWT6Ps3ODUy) | Group | IDO-style — utility narrative required |
| [@tonraffles](https://t.me/tonraffles) | Channel | Raffle tooling — optional community event |

**Avoid** as primary promo: meme pump channels (`@pumpers`, `@gaspump`, etc.) — wrong audience for utility + scam association.

---

## Tier 5 — CEX communities (long shot)

Only after CG/CMC + volume: [@OKXOfficial_English](https://t.me/OKXOfficial_English), [@MEXCEnglish](https://t.me/MEXCEnglish), etc. Use for **listing request**, not shill.

---

## Copy-paste templates

### A — Builder / DeFi chat (STON.fi, Tact)

```
Phalanx (PLX) — utility jetton on TON mainnet for our open-source Tokenization Toolkit
(Tact JettonMinter, vesting, -50% PLX deploy fees, burn-on-receipt).

Live Ston.fi pool: https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
Site: https://plx.foundation/plx-token
Contracts: https://github.com/phalanx-foundation/plx-token
Tonkeeper assets PR: https://github.com/tonkeeper/ton-assets/pull/5540

Not financial advice — looking for builders to try testnet/mainnet deploy flow.
```

### B — Partnership DM (STON.fi / DeDust)

```
Subject: PLX utility jetton — live pool on STON.fi, toolkit on plx.foundation

Hi — Phalanx Foundation deployed audited PLX (TEP-74) + live PLX/TON pool.
We're an infra/tooling project (not meme): open repo, transparency docs, LP ~$34 seeded.

Would you consider a community spotlight or builder quest cross-post?
Channel: https://t.me/phalanxfoundation
Pool: https://app.ston.fi/pools/EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq
```

### C — TON Builders Portal (preferred over cold TG)

Register at https://ton.org/en/ton-ecosystem-support — vertical **Simplified DeFi** or **Telegram In-App Economy**, stage **Launch**, attach Mini App / toolkit demo when ready.

---

## Automation (repo)

| Script | Non-Telegram marketing |
|--------|------------------------|
| `scripts/plx-listing-automation.py` | DexScreener/TonAPI/DYOR checks, quest post, PR nudge |
| `scripts/plx-fundraising-automation.py` | GitHub funding issues (TON grant, Gitcoin, etc.) |
| `scripts/plx-branding-swap.py` | Disclosed micro-MM (off until whitelist + env) |
| `.github/workflows/listing-automation.yml` | Cron every 6h |
| `.github/workflows/fundraising-automation.yml` | Weekly |

Enable in `.env`: `LISTING_AUTOMATION_ENABLED=true`, `FUNDRAISING_AUTOMATION_ENABLED=true`.

---

## Safety

- Verify **@handle** and **.io/.foundation** URLs — drainer clones mimic STON.fi/DeDust/Tonkeeper.
- Never share seed phrase; support never DMs first.
- Disclose team swaps per [`TRANSPARENCY.md`](TRANSPARENCY.md).
