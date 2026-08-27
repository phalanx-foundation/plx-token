# TonAPI escalation — PLX jetton catalog missing after admin revoke

**Priority:** High — mainnet jetton catalog `entity not found` after admin revoke.

## Jetton

- **Symbol:** PLX (Phalanx)
- **Minter (friendly):** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`
- **Minter (raw):** `0:9b69426a89122ec3953e03fb546132b899d1f42f7ee814cbf178c103184e6755`

## Symptom

`GET https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` → **404 entity not found**

Meanwhile:

- Account is **active** (`jetton_master`), holds ~1.86 TON, code+data present
- Holders still indexed; jetton wallets show PLX balances / metadata
- toncenter `get_jetton_data` returns total supply **1e9**, mintable **0**, on-chain metadata Phalanx/PLX OK

## Likely cause

Revoke used Acton `DropMinterAdmin` which set storage admin to **null** (`addr_none` / empty).  
TEP-74 specifies `admin_address` in `get_jetton_data` as **MsgAddressInt**.  
Official docs revoke path is transfer admin to burn address `UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ` (std address, zero hash).

Empty admin encoding after revoke appears to desync TonAPI jetton catalog entity.

## Example revoke transaction

- Event / tx related: `0674e76aac6ffded…` (Deployer → minter, DropMinterAdmin / `0x7431f221`, ~0.05 TON, ok)

## Request

Please **force reindex** jetton master `0:9b69426a…e6755` / `EQCba…` so `/v2/jettons/{id}` returns metadata + verification again.

We understand mint admin cannot be restored; only catalog visibility must return.

## Contact

Phalanx Foundation — plx.foundation / api.plx.foundation
