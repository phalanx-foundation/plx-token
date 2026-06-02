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

- [ ] `curl -I https://plx.foundation/plx-logo.png` → HTTP 200, HTTPS
- [ ] TonAPI: `GET https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS` → `metadata.image` matches URL above
- [ ] Total supply = `1000000000000000000` nano (1B PLX)
- [ ] Follow upstream `ton-assets` folder layout and naming in their README

## Related contracts (for reviewers, not separate jetton entries)

| Contract | Address |
|---|---|
| Team Vesting | `EQCs-Y2wb83zqjCpRUMiZoKLUqhI3qd6tWWm4ycZBp6lsD5l` |
| PaymentSplitter | `EQBC3QoFri_IENOzVfMpHzs2Yr5_dJpzNsRNqT-XB173jSlv` |

## Status

- [ ] PR opened to `tonkeeper/ton-assets`
- [ ] MyTonWallet listing (if applicable)
- [ ] Tonviewer / Tonscan label requests ([`TRANSPARENCY.md`](TRANSPARENCY.md))
