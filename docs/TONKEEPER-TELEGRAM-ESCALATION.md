# Eskalasi Tonkeeper lewat Telegram (resmi)

> Ekosistem TON memang dominan di Telegram. Untuk **verifikasi jetton / hapus SCAM**, jalur **utama tetap PR GitHub** [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) — Tonkeeper menulis: *"All communication regarding the Pull Request … will take place on the request page."*  
> Telegram = **saluran pendukung** ke support resmi, bukan pengganti PR.

---

## Hanya akun resmi (anti penipuan)

| Resmi | Bukan support verifikasi |
|-------|---------------------------|
| Bot **[@tonkeeper](https://t.me/tonkeeper)** | DM random yang klaim "admin Tonkeeper" |
| Email support@tonkeeper.com | Orang yang minta bayar "fast verify" |
| Berita [@tonkeeper_news](https://t.me/tonkeeper_news) | Channel tidak baca PR per token |

**Tonkeeper tidak pernah** chat Anda duluan atau minta 24 kata. Hanya **Anda** yang buka bot dan kirim pesan.

---

## Langkah (2 menit, dari HP)

1. Buka **https://t.me/tonkeeper**
2. Tap **Start** / **Mulai**
3. **Salin-tempel** pesan di bawah (English — tim support biasa pakai ini)
4. Jika diminta, lampirkan link PR — jangan kirim mnemonic

---

## Pesan siap kirim (copy-paste)

```
Hello Tonkeeper support,

Phalanx Foundation (PLX) mainnet jetton shows SCAM / TonAPI blacklist on a legitimate deploy.

Minter: EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
GitHub PR (verification): https://github.com/tonkeeper/ton-assets/pull/5468
Issue: https://github.com/tonkeeper/ton-assets/issues/5475

Deploy TX: https://tonscan.org/tx/9b15fddc37e4babda95e2814e7335f9c9fa44b2d5c323a545b4756c103c45e8f
Contracts: https://github.com/phalanx-foundation/plx-token
Website: https://plx.foundation/plx-token

PR replaces legacy jettons/PLX.yaml (Planet X) with our Phalanx metadata.
admin.is_scam = false. Genesis 1B PLX documented.

Please escalate review/merge of PR #5468 or tell us what is missing.

Thank you — Phalanx Foundation
```

---

## Versi pendek (jika bot batasi panjang)

```
PLX mainnet false SCAM label. PR https://github.com/tonkeeper/ton-assets/pull/5468
Minter EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS
Please escalate merge. Open-source: phalanx-foundation/plx-token
```

---

## Setelah kirim

| Yang terjadi | Yang tidak |
|--------------|------------|
| Support mungkin arahkan ke tim assets / percepat antrian | Merge instan di chat |
| Tetap pantau komentar di **PR #5468** | Bayar siapa pun untuk "un-scam" |

Cek selesai:

```powershell
curl.exe -sS "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | findstr verification
```

`whitelist` = SCAM/FAKE hilang (refresh Tonkeeper ~15–60 menit).

---

## Phalanx di Telegram (proyek Anda)

| Akun | Peran |
|------|--------|
| [@phalanxfoundationbot](https://t.me/phalanxfoundationbot) | Bot resmi Phalanx (di metadata jetton) |
| Bukan channel Tonkeeper | Jangan spam @tonkeeper_news dengan promo token |

---

## Agent vs Anda

- **Agent:** lanjut komentar di PR #5468 / issue #5475 (GitHub).
- **Anda (opsional, sekali):** kirim pesan di atas ke **@tonkeeper** — ini yang paling cocok permintaan "pakai Telegram".

*Terakhir diperbarui: 2026-06-03*
