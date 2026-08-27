# Post Drop-Admin Indexer Recovery

## What broke

PLX genesis used toolkit `DropMinterAdmin` which set `adminAddress = null` (`addr_none` / empty stack slot).

- [TEP-74](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md) `get_jetton_data` expects `admin_address` as **MsgAddressInt**.
- Official revoke path ([docs.ton.org — Create a jetton](https://docs.ton.org/contracts/standard/tokens/jettons/create)): transfer admin to burn address `UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ` (workchain 0 + zero hash).
- After null-drop, TonAPI `GET /v2/jettons/{minter}` returned **entity not found** even though the account stayed active, holders kept balances, and `get_jetton_data` still returned supply/metadata via toncenter.

## What cannot be undone

| Item | Status |
|------|--------|
| Mint admin on PLX genesis | **Gone forever** (no admin → no upgrade / change-admin) |
| PLX supply / balances / on-chain metadata | **Intact** — do not remint |
| TonAPI / explorer catalog visibility | **Recover via reindex / poke** |

## Compliance matrix

| Path | Admin encoding | mintable | Indexer-safe? |
|------|----------------|----------|---------------|
| Official docs burn revoke | MsgAddressInt burn | typically still flagged per FunC; we set mintable=false when admin==burn | Yes |
| Legacy toolkit null-drop | none / empty | false | **No** (TonAPI catalog break) |
| Fixed toolkit DropMinterAdmin | MsgAddressInt burn | false when burn | Yes (new deploys only) |

## Client / product impact

If a toolkit user ran null-drop on mainnet, explorers may hide the jetton catalog entry while wallets still show balances. That looks like “token disappeared” and destroys trust.

**Mitigation shipped:** dashboard Drop Admin TX is **hard-disabled** (`DROP_ADMIN_TX_ENABLED=false`). UI shows suspended notice pointing to official burn path. `buildDropMinterAdminPayload` throws.

## Recovery steps for PLX

1. Verify on-chain: account active, holders > 0, toncenter `get_jetton_data` OK.
2. TopUpTons / small TON transfer to minter to poke indexers.
3. Poll `GET https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` until HTTP 200.
4. Escalate to TonAPI / opentonapi with event hash + empty-admin evidence (see `docs/TONAPI-PLX-REINDEX-ESCALATION.md`).
5. Site fallbacks: `plx-stats-data` rebuilds from holders + canonical metadata when catalog 404.

## Code fixes (new tokens)

- `contracts/jetton-utils.tolk`: `BURN_ADMIN_ADDRESS`, `isActiveMinterAdmin`, `jettonDataAdminAddress`
- `JettonMinter` / `FeeJettonMinter` `DropMinterAdmin` → store burn, not null
- `get_jetton_data` always returns MsgAddressInt; `mintable` false when admin is burn/null
- Dashboard kill switch until burn-path TonConnect payload is wired and tested

## Do not

- Remint / replace PLX minter address and call it the same token
- Claim Deployer mint rights can be restored
- Re-enable null-drop in dashboard
