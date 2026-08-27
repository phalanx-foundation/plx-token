# Eskalasi TonAPI lewat Telegram (@tonapi_bot)

> **Hanya Telegram app** ke akun resmi TonAPI: **[@tonapi_bot](https://t.me/tonapi_bot)**.  
> Jangan email. Jangan @tonkeeper untuk kasus katalog `/v2/jettons` 404 (itu jalur SCAM/assets dulu).

---

## Langkah

1. Buka https://t.me/tonapi_bot (Telegram app)
2. Tap **Start**
3. Tempel pesan di bawah (sudah di clipboard / `tmp/tonapi-telegram-message.txt`)
4. Kirim — lampirkan issue GitHub bila diminta

---

## Pesan siap kirim

```
Hello TonAPI support,

Urgent: mainnet jetton catalog 404 after admin revoke.

Minter: EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS (PLX / Phalanx)
GET https://tonapi.io/v2/jettons/EQCba… → entity not found
Account still active; holders + on-chain metadata OK; toncenter get_jetton_data OK (mintable=0).

GitHub: https://github.com/tonkeeper/opentonapi/issues/963
Site: https://plx.foundation/plx-token

Please force-reindex this jetton master so /v2/jettons returns metadata again.

Thank you — Phalanx Foundation
```

## Cek sukses

```powershell
curl.exe -sS "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
```

HTTP 200 + symbol PLX = visibility pulih.

---

## Referensi lain (bukan untuk kasus ini)

| Kanal | Untuk |
|-------|--------|
| [@tonkeeper](https://t.me/tonkeeper) | SCAM / ton-assets verifikasi (lama) |
| Email support@tonkeeper.com | **Jangan** untuk reindex katalog TonAPI |

*Terakhir diperbarui: 2026-08-28*
