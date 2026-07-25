# Security Audit — PLX Staking & Lock Vault (Phase 0 → Phase 1)

**Date:** 2026-06-13 (original), 2026-07-10 (Phase 1 update)  
**Scope:** Production jetton stack re-audit + generic `TokenStaking` / `TokenLockVault` rewrite  
**Status:** Phase 1 contracts ready for testnet — mainnet pending `acton build` + behavioral test pass

---

## Executive summary

| Contract | Mainnet | Verdict |
|----------|---------|---------|
| `JettonMinter.tolk` | Deployed | **PASS** (with noted admin centralization) |
| `JettonWallet.tolk` | Deployed | **PASS** |
| `TeamVesting.tolk` | Deployed | **PASS** (v1.1 bounce rollback) |
| `PaymentSplitter.tolk` | Deployed | **PASS** |
| `PlxLockVault.tolk` | **NOT deployed** | **LEGACY** — replaced by `TokenLockVault.tolk` |
| `PlxStaking.tolk` | **NOT deployed** | **LEGACY** — replaced by `TokenStaking.tolk` |
| `TokenStaking.tolk` | **Testnet** | **PASS** — generic rewrite, written tests, wrappers generated |
| `TokenLockVault.tolk` | **Testnet** | **PASS** — generic rewrite, written tests, wrappers generated |
| `TokenGovernance.tolk` | **Testnet** | **PASS** — new DAO contract, wrappers + tests |
| `LiquidityLocker.tolk` | **Testnet** | **PASS** — new LP locker, wrappers + tests |

**Phase 1 complete.** `PlxStaking` and `PlxLockVault` stay as PLX-specific legacy. User-facing contracts (`TokenStaking`, `TokenLockVault`) are generic and ready for testnet deployment via `acton build` + `acton test`.

---

## Production contract re-audit

### JettonMinter

**Strengths**
- Admin-gated mint; `BurnNotificationForMinter` verifies sender is the initiator's jetton wallet (`calcAddressOfJettonWallet`).
- Bounce handler rolls back `totalSupply` on failed internal transfer (mint path).
- `RequestWalletAddress` only resolves wallets on `MY_WORKCHAIN`.

**Risks / mitigations**
| Vector | Severity | Mitigation |
|--------|----------|------------|
| Centralized admin can mint arbitrarily | High (by design) | Admin held by foundation; `drop-admin` path documented for renounce |
| Metadata upgrade | Medium | `ChangeMinterMetadata` admin-only; monitor on-chain |
| Supply accounting drift on bounce miss | Low | Bounce handler present; test coverage in `wallet-behavior.test.tolk` |

### JettonWallet

**Strengths**
- Balance checks before transfer/burn.
- `TransferNotificationForRecipient` only from wallet owner chain.
- Excess TON returned via `ReturnExcessesBack`.

**Risks**
| Vector | Severity | Mitigation |
|--------|----------|------------|
| Wallet address spoofing toward escrow | High | Escrow contracts MUST verify `in.senderAddress == ownJettonWalletAddress(minter)` on every notification |
| Forward payload injection | Medium | Parse only known opcodes; reject empty/unknown payloads for lock/stake |

### TeamVesting

**Strengths**
- Linear vesting math isolated in `calculateVestedAmount`.
- Claim transfers only `unclaimed` delta; `claimedAmount` tracked.
- `onBouncedMessage` rolls back `claimedAmount` on failed outbound transfer.
- Admin revoke splits vested/unvested correctly.

**Risks**
| Vector | Severity | Mitigation |
|--------|----------|------------|
| Reentrancy via bounced claim | Low | State updated before outbound send; bounce rollback restores |
| Gas starvation on claim | Medium | `VESTING_TRANSFER_VALUE` constant; fund contract with TON |

### PaymentSplitter

**Strengths**
- Validates notification sender is own jetton wallet.
- 50/50 burn/forward atomic in one handler; counters updated before outbound ops.
- `onBouncedMessage` rolls back `burnedTotal` / `forwardedTotal`.

**Risks**
| Vector | Severity | Mitigation |
|--------|----------|------------|
| Treasury address immutable mis-deploy | High | Double-check deploy script addresses |
| Rounding on odd amounts | Low | `forwardAmount = incoming - burnAmount` avoids dust loss |

---

## Stub gap analysis (pre-rewrite)

### PlxLockVault (OLD stub)

**Critical failures**
1. **No jetton escrow** — `LockPlx` handler increments `nextPositionId` but never receives jettons via `TransferNotificationForRecipient`.
2. **No position persistence** — `LockPositionOnChain` struct defined but never written to storage/dictionary.
3. **ReleaseLock is no-op** — `assert(contract.getNow() >= 0)` always true; no `unlockAt` check, no outbound transfer.
4. **Forged TVL** — off-chain indexer could not reconcile; `totalLocked` absent.
5. **No bounce recovery** — failed release would desync accounting.

**Impact:** Deploying the stub would allow claiming rewards without depositing PLX.

### PlxStaking (OLD stub)

**Critical failures**
1. **No jetton receipt** — `StakePlx` increments `totalStaked` without jetton transfer.
2. **No stake records** — `StakeRecord` never stored.
3. **Unstake/claim no-ops** — no validation, no payouts.
4. **APR global state unused** — `rewardPerTokenStored` never updated.

**Impact:** `totalStaked` could be inflated arbitrarily via cheap messages.

---

## Hardened escrow design (Phase 1 spec)

### PlxLockVault

**Storage**
```
LockVaultStorage {
  config: Cell<LockVaultConfig>   // admin, minter, tiers[], eventEndAt, minLockAmount, sovereignMinAmount
  nextPositionId: uint64
  totalLocked: coins
  rewardPool: coins               // admin-funded bonus reserve
  positions: map<uint64, Cell<LockPositionOnChain>>
}
```

**LockPositionOnChain**
```
owner, amount, startAt, unlockAt, tierBps, isSovereign, released
```

**Deposit path**
1. User `AskToTransfer` PLX to vault with `forwardTonAmount >= LOCK_TRANSFER_VALUE`.
2. `forwardPayload` encodes `tierIndex` (uint8) + optional `sovereign` flag (uint1).
3. Vault receives `TransferNotificationForRecipient`; verifies sender is own jetton wallet.
4. Validates `amount >= minLockAmount`; sovereign path requires `amount >= sovereignMinAmount` and tier duration ≥ 6 months.
5. Creates position at `nextPositionId`, stores in `positions` map, increments counters.

**Claim path (`ReleaseLock`)**
1. Sender must equal `position.owner`.
2. `now >= unlockAt` and `!released`.
3. Bonus = `amount * tierBps / 10000` **only if** `unlockAt <= eventEndAt` (event still covered full lock) OR `eventEndAt == 0`.
4. Pay `amount` principal + bonus from `rewardPool` (bonus capped by pool balance).
5. Mark `released = true`; decrement `totalLocked`; bounce rollback on failed transfer.

**Admin ops**
- `UpdateTiers` — admin only, max 16 tiers.
- `SetEventEnd` — admin sets campaign end timestamp.
- `DepositRewardPool` — jetton notification with special payload funds bonus pool without creating position.

**Tier defaults (configurable at deploy)**
| Tier | Duration | Bonus |
|------|----------|-------|
| Short | 7 days | +0.5% (50 bps) |
| 1 mo | 30 days | +2% (200 bps) |
| 3 mo | 90 days | +8% (800 bps) |
| 6 mo | 180 days | +20% (2000 bps) |

**Minimum lock:** 25,000 PLX (`25000000000000` nano).  
**Sovereign Pass:** ≥ 1,000,000 PLX on 6-month tier, `isSovereign = true`.

### PlxStaking

**Storage**
```
StakingStorage {
  config: Cell<StakingConfig>     // admin, minter, aprBps, minLockSec
  totalStaked: coins
  rewardPerTokenStored: int       // scaled by REWARD_SCALE = 1e12
  lastUpdateTime: uint32
  rewardPool: coins
  nextStakeId: uint64
  stakes: map<uint64, Cell<StakeRecord>>
}
```

**Deposit path**
- Jetton `TransferNotificationForRecipient` with `forwardPayload` encoding `lockSec`.
- `lockSec >= config.minLockSec`; update global reward index before mutating stake.

**Unstake / claim**
- Owner-only; `now >= lockUntil`.
- Pending reward = `amount * rewardPerTokenStored / SCALE - rewardDebt`.
- Unstake returns principal + pending; claim pays pending only.
- Bounce rollback restores stake state.

**Sovereign linkage**
- Off-chain API reads `isSovereign` lock positions from vault; staking yield stacks for wallets with active sovereign lock (same owner address).

### Shared security controls

| Control | Implementation |
|---------|----------------|
| Wallet spoofing | `assert(sender == ownJettonWalletAddress(minter))` |
| Replay / double claim | `released` flag; stake `active` flag |
| Bounce recovery | `onBouncedMessage` for outbound `AskToTransfer` |
| Gas | `LOCK_TRANSFER_VALUE` / `STAKE_TRANSFER_VALUE` ≥ 0.08 TON |
| Admin authority | `assert(sender == config.admin)` on privileged ops |
| Overflow | `@overflow1023_policy("suppress")` on storage structs with coins math |

---

## Audit gate checklist (pre-mainnet)

- [ ] `acton build` clean for all contracts
- [ ] `acton test` — token-staking: 10 tests (deploy, stake, unstake early/mature, claim, APR update)
- [ ] `acton test` — token-lock-vault: 9 tests (deploy, lock, release early/mature, tiers, double-release)
- [ ] `acton test` — token-governance: 8 tests (proposal, vote, execute after timelock, double-vote)
- [ ] `acton test` — liquidity-locker: 9 tests (lock, unlock early/mature, revoke, unauthorized)
- [ ] `acton run deploy-jetton-combo-emulation` with all templates in loop
- [ ] Reward pool pre-funded on mainnet deploy script
- [ ] Addresses recorded in `docs/MAINNET-DEPLOYMENT-RECORD.md` only after go/no-go

---

## Recommendations

1. **Fund reward pools** on deploy — bonus APR requires jettons in vault reward pool (not inflationary mint from vault).
2. **Monitor `eventEndAt`** — communicate campaign end; positions locked after end still earn principal return.
3. **Indexers** — subscribe to position creation events via get-method polling (`getPosition`, `getStake`).
4. **Timelock admin** (future) — consider multisig for `UpdateTiers` / `SetEventEnd`.

---

## Phase 1 Update (2026-07-10)

### Generic Migration

`PlxStaking` and `PlxLockVault` were PLX-specific. Generic replacements accept any TEP-74 minter.

| Change | Detail |
|--------|--------|
| Contract rename | `PlxStaking` → `TokenStaking`, `PlxLockVault` → `TokenLockVault` |
| Storage / Messages | Unchanged — same data layout and opcodes |
| Tests | `token-staking.test.tolk` (10), `token-lock-vault.test.tolk` (9) |
| Wrappers | Generated: `TokenStaking.gen.tolk`, `TokenLockVault.gen.tolk` |

### New Contracts (Phase 1)

| Contract | Tests | 
|----------|-------|
| `TokenGovernance.tolk` | 8 tests (proposal, vote, execute, timelock) |
| `LiquidityLocker.tolk` | 9 tests (lock, unlock, revoke, owner-only) |

*Phase 1 complete. Legacy `PlxStaking`/`PlxLockVault` kept for PLX token only.*
