# Security Policy

The Phalanx (PLX) team takes security seriously. This document explains how to
report vulnerabilities and what to expect from us in return.

## Supported Versions

The contracts deployed on TON **mainnet** at the addresses published in
[`docs/TRANSPARENCY.md`](docs/TRANSPARENCY.md) are the only versions covered
by this policy. Testnet deployments are best-effort and may be reset.

## Reporting a Vulnerability

If you discover a vulnerability that could lead to fund loss, supply
manipulation, or denial-of-service of the contracts:

1. **Do NOT open a public GitHub issue.** Public disclosure before a fix gives
   attackers a window to exploit live contracts.
2. **Email the security contact** (TBD — to be published before mainnet
   launch). Include:
   - A clear description of the vulnerability
   - Steps to reproduce (PoC test against `acton test` or testnet preferred)
   - Suggested mitigation if you have one
   - Whether you'd like public credit after the fix is shipped
3. We will acknowledge your report within **72 hours** and work on a fix in
   private.

## Scope

In scope:

- All contracts under `contracts/` (`JettonMinter.tolk`, `JettonWallet.tolk`,
  `TeamVesting.tolk`)
- Deployment scripts under `scripts/` to the extent they affect contract
  initialization or admin transitions

Out of scope:

- Phishing, social engineering, or attacks on individual wallet holders
- Issues in the underlying TON protocol or Acton/Tolk toolchain (please
  report those upstream)
- Vulnerabilities in third-party DEXes (Ston.fi, DeDust) that we list against

## Bug Bounty

A formal bug bounty will be announced together with the third-party security
audit (planned post-mainnet, when volume justifies the cost). Until then,
responsible disclosures are gratefully acknowledged in release notes.

## Hardening Already in Place

For transparency, the following defences are currently in effect:

- Built on the audited TEP-74 Jetton standard (no custom token transfer logic)
- 60+ unit tests covering admin, governance, gas, protocol validation, state
  init, vesting, wallet behavior, and bounce handling
- On-chain enforced 6-month linear vesting for the team allocation
- Deterministic, reproducible deployment scripts so anyone can verify cell
  hashes
- Planned: minter admin renounced 7 days post-mainnet to permanently fix the
  total supply
- Planned: LP tokens locked for at least 12 months after pool creation
- Planned: third-party security audit before significant volume

Thank you for helping keep Phalanx (PLX) and its holders safe.
