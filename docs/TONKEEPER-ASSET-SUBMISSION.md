# Tonkeeper / ton-assets — PLX mainnet submission

Use this checklist when opening a PR to [tonkeeper/ton-assets](https://github.com/tonkeeper/ton-assets).

## Jetton (mainnet)

| Field | Value |
|---|---|
| **Network** | mainnet |
| **Minter address** | `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` |
| **Name** | Phalanx |
| **Symbol** | PLX |
| **Decimals** | 9 |
| **Image** | `https://plx.foundation/plx-logo.png` |
| **Description** | Utility token for the Phalanx Foundation ecosystem on TON — audited Jetton + vesting + toolkit payment rail. |
| **Website** | https://plx.foundation/plx-token |
| **GitHub** | https://github.com/phalanx-foundation/plx-token |
| **Explorer** | https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS |

## Verification before PR

- [x] `curl -I https://plx.foundation/plx-logo.png` → HTTP 200, HTTPS
- [x] TonAPI: `GET https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` → `metadata.image` matches URL above
- [x] Total supply = `1000000000000000000` nano (1B PLX)
- [x] Follow upstream `ton-assets` folder layout (`jettons/PLX.yaml`)

## Related contracts (for reviewers, not separate jetton entries)

| Contract | Address |
|---|---|
| Team Vesting | `EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l` |
| PaymentSplitter | `EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv` |

## Status

- [x] PR opened to `tonkeeper/ton-assets` — **https://github.com/tonkeeper/ton-assets/pull/5468** (2026-06-02, branch `KelvinHernata:add-plx-mainnet-jetton`)
- [ ] PR **merged** by Tonkeeper (typical review: beberapa hari; gratis, tanpa bayar)
- [ ] Setelah merge: tunggu cache wallet 15–60 menit → label “scan” / unverified hilang di Tonkeeper
- [ ] MyTonWallet listing (if applicable)
- [ ] Tonviewer / Tonscan label requests ([`TRANSPARENCY.md`](TRANSPARENCY.md))
