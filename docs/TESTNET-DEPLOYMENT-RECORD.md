# Testnet Deployment Record

> Live deployment evidence for Phalanx (PLX) on TON **testnet**.
> Reproducible artifact: anyone can re-run `acton script scripts/deploy-distribution.tolk --net testnet` to verify identical contract bytecode and metadata cell hashes.

## Contracts (testnet, live)

| Contract | Address | Explorer |
|---|---|---|
| **Jetton Minter** | `kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV` | [Tonviewer](https://testnet.tonviewer.com/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV) · [Tonscan](https://testnet.tonscan.org/address/kQAslxaUshiiqy5FrTbYHbBpjBgmcyTHB8vKKCemFKp508xV) |
| **Team Vesting** | `kQDNPoiPbKXwjt4i9SqtBmvbUlMgWz1jCR7M5Uwjj5fI8t1l` | [Tonviewer](https://testnet.tonviewer.com/kQDNPoiPbKXwjt4i9SqtBmvbUlMgWz1jCR7M5Uwjj5fI8t1l) |

## Distribution Wallets

| Role | Holder Address | Jetton Wallet | Balance |
|---|---|---|---|
| LP | `kQD4-ER4sDGmw4PcPPJ-AwLYG9TORvZ5sJ-xNKthunKz0AOP` | `kQD40ZukE5EYYj5if8v_YreFUADlC1oypqHR2or98SK3BIcz` | 400,000,000.000000000 PLX |
| Treasury | `kQCAfIuFFlS8RJyYQU7pFaN1XqcO8V4lZl-SH8Ca950XqGal` | `kQCAsOhlqKqWR5f5oe0XCxxVv6dnYliixxp2u-nN6W04ewkR` | 250,000,000.000000000 PLX |
| Community | `kQAZWyvZBkUctnlbqP8EVTzh43g7JcYod9NqYjenRbf2nPiC` | `kQAZk1kDm2UrPA7-wg8uDVQQQUD08bafGLX_Boqi0gwygzNI` | 200,000,000.000000000 PLX |
| Marketing | `kQD51illBEG2sQ5do-28UoVDyiQbyRMVagzfwnWV7QCginMA` | `kQD5CMgQIjQ4be-bOyzdI3jfVS-XlgEVl5nUCBoN6elAFMO-` | 50,000,000.000000000 PLX |
| Vesting (locked) | (vesting contract) | `kQDN6jtS3Q_Ex2zivRFNwhmSPNu3ZdgysDUsrg-OdrBPetGO` | 100,000,000.000000000 PLX (linear unlock 6mo) |
| Beneficiary | `kQDT6fR2DU48L49-EEBzjbfftxu2bL1VoYDAhB2CycEu_8wr` | `kQDTWpZZX7C6ondaSN0YAszWQC9HIBXiySwbaYL4oWNBCtI6` | grows as `claim-vesting` is called |

**Total supply on-chain**: `1,000,000,000,000,000,000` nano-PLX = 1,000,000,000 PLX

## Genesis Transactions

| Step | TX | Tonscan |
|---|---|---|
| Minter deploy | `17879144...d1109` | [link](https://testnet.tonscan.org/tx/17879144d22c2c6e69209515ebb19563a7a76b6b17d44d7f8c28cca6f4dd1109) |
| Vesting deploy | `dac06947...a7b7b0` | [link](https://testnet.tonscan.org/tx/dac0694705d37ef8957094fcfd54fb16ff4fddcd9b759047c81399a9d5cab7b0) |

## Vesting Contract Live State

```
beneficiary  = kQDT6fR2DU48L49-EEBzjbfftxu2bL1VoYDAhB2CycEu_8wr
admin        = kQB1GGwuoPV1vS2DjEg-weTPy5_HQU4ipqQm6KO05EyqEizN (legacy testnet deployer — see Security Drill below)
totalAmount  = 100,000,000,000,000,000 nano-PLX (= 100M PLX)
startTime    = 1779199165 (Tue 19 May 2026 13:59:25 UTC)
duration     = 15,552,000 seconds (180 days = 6 months)
```

> **Note:** the vesting contract's admin was set at deploy time and is immutable for
> the lifetime of this testnet deployment. On mainnet, deployment will use a fresh
> wallet that has never been touched outside its hardware wallet / secure
> environment.

After 180 days from `startTime`, full 100M PLX will be claimable by the beneficiary.

The vesting contract has been **end-to-end tested** on testnet:

```
[claim-vesting] caller=plx-deployer
[claim-vesting] claimable now: 5,870,627,572,016 nano-PLX
... transaction processed (5 internal txs) ...
[claim-vesting] OK; new claimed amount: 5,883,487,654,320 nano-PLX
```

The beneficiary wallet `kQDTWpZZX...kQtI6` received the unlocked tokens.

## Test Suite

```
acton test
... 60 passed in 7 files
```

Coverage breakdown:

- `admin-and-governance.test.tolk` — 14 tests
- `bounce-handling.test.tolk` — 3 tests
- `gas.test.tolk` — 13 tests
- `protocol-validation.test.tolk` — 7 tests
- `state-init.test.tolk` — 2 tests
- `vesting.test.tolk` — 12 tests (custom)
- `wallet-behavior.test.tolk` — 9 tests

## Reproducibility

To reproduce this deployment from scratch:

```bash
git clone https://github.com/phalanx-foundation/plx-token.git
cd plx-token
acton build && acton test                  # 60/60 should pass
acton wallet new --local --name plx-deployer --version v5r1 --secure false
acton wallet airdrop plx-deployer
acton wallet airdrop plx-deployer
# ... see docs/DEPLOYMENT.md for the full step-by-step
```

For mainnet, follow `docs/MAINNET-CHECKLIST.md`.

## Security Drill: Deployer Rotation (2026-05-20)

As part of pre-mainnet operational rehearsal, the Phalanx Foundation team performed
a controlled rotation of the testnet deployer wallet to validate the
`ChangeMinterAdmin` → `ClaimMinterAdmin` flow under real network conditions.

| Wallet | Address | Status |
|---|---|---|
| Legacy deployer | `kQB1GGwuoPV1vS2DjEg-weTPy5_HQU4ipqQm6KO05EyqEizN` | **retired** — no longer holds admin authority |
| Active deployer | `kQBg9RFEVaQIh3xVonBxCnIb2Vw19y-rSD4uO1LR0eNH4zT2` | current minter admin |

**Verification:** call `acton script scripts/info.tolk --net testnet` and check
`JETTON ADMIN_ADDRESS` — it now returns the active deployer above.

**Rationale:** simulating a wallet rotation on testnet validates that our
incident-response runbook works end-to-end before any real funds are at stake on
mainnet. The legacy deployer retains a small residual TON balance (~0.6 TON,
testnet only, no monetary value) and no jetton admin authority.

For mainnet, distribution wallets, deployer, and team-vesting beneficiary will
be generated fresh in a hardened environment (see `docs/MAINNET-CHECKLIST.md`)
and **never used for any other purpose**.

---

*Deployed by the Phalanx Foundation team using [Acton](https://ton-blockchain.github.io/acton/) + [Tolk](https://docs.ton.org/develop/tolk) on the [TON blockchain](https://ton.org).*
