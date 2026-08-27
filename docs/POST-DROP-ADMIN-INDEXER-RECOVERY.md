# Post Drop-Admin Indexer Recovery

## What broke

PLX genesis used an older `DropMinterAdmin` that set `adminAddress = null` (`addr_none`).

- [TEP-74](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md) expects `admin_address` as **MsgAddressInt**.
- Official revoke ([docs.ton.org](https://docs.ton.org/contracts/standard/tokens/jettons/create)): transfer admin to burn `UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ`.
- TonAPI `GET /v2/jettons/{minter}` returned **entity not found** after null-drop.

## Fixed toolkit path (tool stays enabled)

Dashboard **Drop Admin** stays active. It sends `DropMinterAdmin` (`0x7431f221`).  
Updated `JettonMinter` / `FeeJettonMinter` store **burn MsgAddressInt** (not null), set `mintable=false`, and always return MsgAddressInt from `get_jetton_data`.

| Item | Status |
|------|--------|
| Mint admin on PLX genesis | Gone forever (already null-dropped) |
| New client tokens (new code) | Drop Admin → burn address (indexer-safe) |
| TonAPI catalog for PLX | Reindex / poke — see `TONAPI-PLX-REINDEX-ESCALATION.md` |

## Do not

- Remint / replace PLX minter and call it the same token
- Claim Deployer mint rights can be restored
- Reintroduce null/addr_none admin encoding
- Disable the Drop Admin tool instead of fixing burn-path behavior
