# Akuntabilitas: label SCAM, LP, dan apa yang agent tanggung jawabkan

**Untuk operator Phalanx** — tanpa janji kosong.

---

## Yang Anda alami (valid)

| Kerugian | Kategori | Bisa dikembalikan agent? |
|----------|----------|---------------------------|
| ~5 TON deploy mainnet | Biaya **wajib** agar kontrak + 1B PLX live | **Tidak** — sudah on-chain, tidak reversible |
| Modal LP (1–2×) | **Opsional** — likuiditas DEX | **Tidak** — TON/PLX di pool milik Anda; agent tidak pegang fiat |
| Waktu + stres | — | Agent lanjut eskalasi **gratis** |

**Agent tidak bisa** mengganti rugi TON/fiat atau **menjamin** PR Tonkeeper lolos. Siapa yang “rugi” jika PR ditolak: **bukan karena deploy ulang**, melainkan **reputasi + LP yang Anda masukkan sebelum SCAM hilang** — makanya aturan di bawah.

---

## Aturan keras (lindungi Anda)

### Jangan keluarkan modal LP lagi sampai:

```bash
curl -s "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | jq -r .verification
```

Harus keluar: **`whitelist`** (bukan `blacklist`).

| Situasi | LP? |
|---------|-----|
| `blacklist` + label SCAM | **Jangan** — risiko reputasi + uang di pool tetap terlihat “scam” |
| `whitelist` + PR merged | Baru pertimbangkan LP (keputusan bisnis Anda) |

**400M PLX di wallet LP tetap aman on-chain** tanpa pool — tidak hilang karena tidak LP.

---

## Apa yang **bisa** agent lakukan (tanpa Anda urus)

| Tindakan | Status |
|----------|--------|
| PR [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) — ganti `PLX.yaml` Planet X → Phalanx | OPEN — sudah 5+ komentar bukti |
| Issue [#5475](https://github.com/tonkeeper/ton-assets/issues/5475) | OPEN |
| Komentar reviewer: konflik ticker PLX lama vs minter baru | Ditambahkan 2026-06-03 |
| Template email `support@tonkeeper.com` | [`TONKEEPER-EMAIL-ESCALATION.md`](TONKEEPER-EMAIL-ESCALATION.md) |
| Pantau TonAPI `verification` | Otomatis / tiap sesi agent |
| Minta Anda top-up TON / LP lagi | **Dilarang** sampai whitelist |

**Satu-satunya yang menutup SCAM:** maintainer Tonkeeper **merge** PR (atau instruksi revisi → kita perbaiki PR dalam 24 jam).

---

## Kenapa PR ini masuk akal (bukan “tebak-tebakan”)

Di repo `ton-assets` **main**, file `jettons/PLX.yaml` masih:

- Minter lama: `EQDHywJXwgB_tIPS0-MurY1FInqmI6PDuyX31RA4hU_lKz1Z` (Planet X)
- Bukan minter Phalanx Anda: `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`

PR #5468 **mengganti** entri itu ke Phalanx — pola normal untuk update jetton, bukan spam PR baru.

---

## Batas tanggung jawab agent (jujur)

| Agent **bertanggung jawab** | Agent **tidak** bertanggung jawab |
|-----------------------------|-----------------------------------|
| Eskalasi PR/issue/email template | Keputusan merge Tonkeeper |
| Dokumen & bukti on-chain benar | Kerugian LP yang sudah Anda lakukan |
| Tidak mengarahkan deploy ulang 5 TON | Timeline reviewer (antrian ratusan PR) |
| Koreksi narasi wallet/SCAM salah | Mengirim email dari inbox Anda (harus Anda klik Send sekali) |

---

## Satu aksi opsional dari Anda (30 detik, gratis)

Kirim email dari template [`TONKEEPER-EMAIL-ESCALATION.md`](TONKEEPER-EMAIL-ESCALATION.md) ke **support@tonkeeper.com** — mempercepat antrian, **bukan** bayar siapa pun.

Selain itu: **Anda tidak perlu urus** — agent lanjut komentar/monitor PR.

---

## Jika PR ditolak (rencana B)

1. Baca alasan penolakan di thread PR.  
2. Agent perbaiki YAML (nama file, field, logo, dll.) dalam **24 jam**.  
3. **Tetap tidak LP** sampai whitelist.  
4. Explorer Tonviewer tetap valid untuk investor yang DYOR.

---

*Terakhir diperbarui: 2026-06-03*
