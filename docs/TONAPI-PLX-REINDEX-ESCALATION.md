# TonAPI escalation — PLX jetton catalog (INTERNAL)

**JANGAN** buka GitHub issue publik dari akun pribadi. Gunakan support TonAPI / email org / bot `phalanx-foundation` saja.

## Symptom

`GET /v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` → 404 entity not found

## On-chain (toncenter `get_jetton_data`)

- supply OK, mintable `0`
- **admin stack = empty tvm.list** (addr_none / null) — akar “beginParse null”; tidak bisa diubah lagi tanpa admin
- metadata Phalanx/PLX cell OK; account active

## Request (template anonim)

Force reindex jetton master `0:9b69426a…e6755` despite empty admin encoding after revoke. Balances/holders/metadata still on-chain.

## History

- Issue publik `tonkeeper/opentonapi#963` dibuka salah dari identitas pribadi → **withdrawn/closed**. Jangan revive dari akun itu.
