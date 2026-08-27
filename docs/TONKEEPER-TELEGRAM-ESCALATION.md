# Eskalasi Tonkeeper lewat Telegram (resmi) — SCAM / ton-assets SAJA

> Untuk **katalog TonAPI 404 / reindex jetton** → pakai **[@tonapi_bot](https://t.me/tonapi_bot)** — lihat [`TONAPI-TELEGRAM-ESCALATION.md`](TONAPI-TELEGRAM-ESCALATION.md).  
> File ini hanya untuk jalur SCAM / ton-assets (bukan email).

---

## Hanya akun resmi (anti penipuan)

| Resmi | Bukan support |
|-------|----------------|
| Bot **[@tonkeeper](https://t.me/tonkeeper)** | DM random "admin Tonkeeper" |
| Email support@tonkeeper.com | Orang yang minta bayar "fast fix" |
| [@tonkeeper_news](https://t.me/tonkeeper_news) | Channel promo |

**Jangan** kirim mnemonic.

---

## Sekarang — visibility PLX hilang di katalog (2026-08-28)

### Buka cepat

1. https://t.me/tonkeeper — Start, tempel pesan di bawah  
2. Atau share prefill: lihat `tmp/tonkeeper-telegram-links.txt` (SHARE_PREFILL)

### Pesan siap kirim (copy-paste)

```
Hello Tonkeeper / TonAPI support,

Phalanx Foundation — urgent indexer request.

Mainnet jetton PLX minter:
EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS

GET https://tonapi.io/v2/jettons/EQCba… returns entity not found (404) after admin revoke.
Account is still active; holders + on-chain metadata OK; toncenter get_jetton_data works (mintable=0).

GitHub issue: https://github.com/tonkeeper/opentonapi/issues/963
Website: https://plx.foundation/plx-token

Please force-reindex this jetton master so catalog/metadata visibility returns.

Thank you — Phalanx Foundation
```

### Cek sukses

```powershell
curl.exe -sS "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS"
```

HTTP 200 + symbol PLX = visibility pulih.

---

## Legacy — hapus SCAM / blacklist (referensi)

Pesan lama + PR #5468 tetap di git history bila perlu. Saat ini fokus **katalog 404**, bukan SCAM.

---

## Agent

- Pantau issue #963 + poll `/v2/jettons` sampai 200.
- Buka @tonkeeper / share link; jika Telegram Web butuh login user → operator tap Start + tempel pesan dari `tmp/tonkeeper-telegram-message.txt`.

*Terakhir diperbarui: 2026-08-28*
