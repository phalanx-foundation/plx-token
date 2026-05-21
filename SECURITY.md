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

## Internal Security Review (2026-05-20)

An internal review against three known TON Jetton failure modes was completed
prior to mainnet preparation. Findings and remediations:

### 1. Bounce-message handling (fake-address rebound risk)

Pattern verified across all contracts: `JettonMinter` and `JettonWallet` both
implement `onBouncedMessage` handlers that restore accounting state when an
inter-contract message fails. `JettonWallet.AskToTransfer` validates the sender
against the canonical wallet-address derivation, preventing forged
`InternalTransferStep` messages from inflating balances.

Initial gap: `TeamVesting` v1.0 lacked a bounce handler and used
`BounceMode.NoBounce` for its outbound `AskToTransfer` calls, which would have
left `claimedAmount` permanently incremented if the inter-contract transfer
failed at the wallet layer.

**Remediation (TeamVesting v1.1):**

- Outbound `AskToTransfer` now uses `BounceMode.Only256BitsOfBody`.
- New `onBouncedMessage` handler decodes the bounced opcode and refunded
  `jettonAmount` from the truncated body and rolls back `claimedAmount`
  accordingly, with an underflow guard that floors the value at zero.

### 2. Gas-management and trapped-TON risk

Pattern verified: `JettonWallet` reserves storage fees and forwards excess via
the `ReturnExcessesBack` pattern, ensuring TON never accumulates inside
wallet contracts beyond their minimum storage reserve.

Initial gap: `TeamVesting` v1.0 had no reserve mechanism and no withdrawal
function, meaning surplus TON forwarded with `ClaimVested` triggers would
accumulate in the contract with no recovery path.

**Remediation (TeamVesting v1.1):**

- `ClaimVested` now sets `sendExcessesTo: in.senderAddress` so unused gas is
  returned to whichever wallet triggered the claim, instead of always to the
  beneficiary regardless of caller.
- A new admin-only `WithdrawTons` opcode (`0x77777703`) lets the configured
  `cfg.admin` rescue any TON dust that does accumulate (e.g. from
  partially-bounced messages or pre-v1.1 deposits) without touching the
  jetton balance held by the contract's wallet. Beneficiary funds are not
  affected.

### 3. Cell-padding / serialization

All inter-contract messages are defined as named structs with explicit Tolk
types (`coins`, `address`, `uint64`) in `contracts/messages.tolk` and loaded
via `lazy *.fromSlice(...)`. There is no manual `loadUint`/`storeUint` in the
business logic outside a single 1-bit empty-payload flag in
`TeamVesting.emptyForwardPayload`, which is correct by inspection.

The bounce handler in v1.1 does call `loadUint(32)` for the opcode and
`loadCoins()` for the jetton amount on bounced bodies; these match the
`AskToTransfer` TLB definition exactly (32-bit opcode + 64-bit queryId +
coins prefix), and reads are guarded by an early-return on an unexpected
opcode.

### Status

- Mainnet deployment will use v1.1 contracts.
- Existing testnet deployment (`kQDNPoiPbKXwjt4i9SqtBmvbUlMgWz1jCR7M5Uwjj5fI8t1l`,
  vesting v1.0) remains as-is and will be retired once mainnet goes live.
  v1.0 has no observed exploit and the failure modes above require an
  inter-contract transfer to actually fail, which has not occurred on the
  live testnet contract.

## Verifying Commits to This Repository

Every commit to `master` on `phalanx-foundation/plx-token` is GPG-signed by the
Phalanx Foundation operator key. Anyone can verify a commit was authored by us
(and not by a compromised account or impersonator) without trusting GitHub's
own UI.

**Operator signing key**

| Field | Value |
|---|---|
| UID | `Phalanx Foundation <ops@phalanx.foundation>` |
| Algorithm | Ed25519 (signing) + Curve25519 (encryption subkey) |
| Fingerprint | `8A8C 5854 2DE1 AA52 64CE  836A 4B53 081F AB6C 5C63` |
| Long key id | `4B53081FAB6C5C63` |
| Created | 2026-05-20 |
| Expires | 2028-05-19 (renewed and announced before expiry) |
| Public key file | [`metadata/phalanx-foundation-public.asc`](metadata/phalanx-foundation-public.asc) |

**How to verify any commit**

```bash
# 1. Clone the repo (or use an existing clone)
git clone https://github.com/phalanx-foundation/plx-token.git
cd plx-token

# 2. Import the published public key
gpg --import metadata/phalanx-foundation-public.asc

# 3. Confirm the fingerprint matches the value in the table above
gpg --fingerprint ops@plx.foundation

# 4. Verify the latest commit (or any specific commit hash)
git log --show-signature -1
git verify-commit <commit-hash>
```

A commit is authentic if and only if the line
`gpg: Good signature from "Phalanx Foundation <ops@phalanx.foundation>"`
appears AND the displayed fingerprint matches the table above.

**Why we self-host the public key instead of relying on GitHub's "Verified" badge**

GitHub will not display its green "Verified" badge for our commits at this
stage because the key is intentionally **not** uploaded to a personal GitHub
account, in order to keep individual contributor identity unlinked from the
project. The cryptographic signature is independent of GitHub's UI, so anyone
who clones the repo and runs `git verify-commit` gets a stronger guarantee
than the badge alone provides. We will register the same key against the
`phalanx-foundation` organisation once GitHub's organisation-level GPG
verification ships, or against `ops@plx.foundation` (active primary UID as of 2026-05-21).

## GPG UID rotation history

| UID | Status | Since |
|---|---|---|
| `Phalanx Foundation <ops@phalanx.foundation>` | Retained on key for historical commit verification | 2026-05-20 |
| `Phalanx Foundation <ops@plx.foundation>` | Primary UID for new signatures | 2026-05-21 |

**If you ever see an unsigned commit on master, treat it as suspect** and
verify with the maintainers via a side channel before trusting it.

Thank you for helping keep Phalanx (PLX) and its holders safe.
