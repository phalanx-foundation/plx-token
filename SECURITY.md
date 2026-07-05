# Security Policy — Phalanx Foundation

## Responsible Disclosure

If you discover a security vulnerability in any Phalanx Foundation smart contract, web application, API, or infrastructure, we encourage you to report it privately so we can address it before public disclosure.

### How to Report

**Email:** security@plx.foundation
**PGP Key:** `4B53 081F AB6C 5C63` (Phalanx Foundation GPG key — available at `https://github.com/phalanx-foundation/plx-token/blob/master/.gpg/plx-foundation.asc`)

Please include:

- A clear description of the vulnerability
- Steps to reproduce (if applicable)
- Affected component(s): contract code, web app, API, infra
- Your assessment of severity
- Any suggested fix (optional)

### What to Expect

1. **Acknowledgment** within 48 hours of receipt.
2. **Status update** within 7 days with our assessment and planned remediation timeline.
3. **Resolution** — we aim to fix critical vulnerabilities within 14 days, high-severity within 30 days.
4. **Public disclosure** — once a fix is deployed, we will publish an advisory in this repository with credit to the reporter (unless you prefer to remain anonymous).

### Scope

The following are in scope:

- Smart contracts in `phalanx-foundation/plx-token`
- Web application at `plx.foundation`
- API at `api.plx.foundation`
- Infrastructure: Ubuntu server, Cloudflare Tunnel, Neon database

The following are **out of scope**:

- Third-party services (Ston.fi, DexScreener, CoinGecko, TonAPI, Tonkeeper, TON blockchain itself)
- Theoretical attacks without a working proof-of-concept
- Social engineering or phishing of Phalanx Foundation team members (please report these privately but do not test them)
- Denial-of-service attacks (DoS/DDoS)
- Vulnerabilities in dependencies that are already publicly disclosed with available fixes

### Safe Harbor

When researching and reporting vulnerabilities under this policy, we consider your activities to be authorized and will not pursue legal action against you. We ask that you:

- Do not exploit the vulnerability beyond what is necessary to demonstrate it.
- Do not access, modify, or delete data that does not belong to you.
- Do not disrupt our services or degrade the experience of other users.
- Give us reasonable time to fix the vulnerability before any public disclosure.

### Recognition

We maintain a public Hall of Fame (below) for security researchers who responsibly disclose vulnerabilities. We do not currently offer monetary bounties, but contributors will be acknowledged publicly and may receive PLX tokens as a token of appreciation at our discretion.

### Hall of Fame

None yet. Be the first.

### Audit History

| Date | Scope | Auditor | Result |
|------|-------|---------|--------|
| 2026-06-13 | PlxLockVault, PlxStaking (stubs) | Internal review | NOT-SAFE-TO-DEPLOY — Phase 1 rewrite pending |
| 2026-06 | JettonMinter, JettonWallet, TeamVesting, PaymentSplitter | Internal review + 60 tests passing | PASS — deployed to mainnet |
| 2026-05-28 | GitHub repos (secrets scan) | Internal audit | CLEAN — no secrets committed to public/private repos |
| Q4 2026 (planned) | Full codebase | External third-party auditor | TBD |

### Vulnerability Disclosure Policy

Last updated: 2026-07-05
Policy version: 1.0.0
