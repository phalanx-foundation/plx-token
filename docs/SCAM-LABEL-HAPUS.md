# Menghapus label SCAM — konteks lengkap (Phalanx PLX)

**Penting:** **Add custom token** di Tonkeeper hanya menampilkan saldo PLX — **TIDAK** menghapus label SCAM. SCAM hilang hanya setelah verifikasi resmi Tonkeeper.

---

## Jawaban singkat dua pertanyaan operator

### Apakah 0,05 TON itu juga uang saya?

**Ya — itu bagian dari dana proyek yang sama**, bukan “uang gratis dari agent”.

| Sumber | Penjelasan |
|--------|------------|
| ~5 TON yang Anda kirim ke deployer | Dipakai **biaya deploy mainnet** (minter, mint 1B, vesting, splitter) |
| ~0,05 TON di treasury/LP/dll. | **Sisa rent/gas** dari transaksi mint genesis (satu alur deploy) |
| 0,03 TON treasury → deployer | **Pemindahan internal** antar wallet proyek — bukan minta top-up baru ke Anda |

Agent **tidak bisa** mencetak TON mainnet dari udara. Yang dilakukan: menggeser sedikit TON **yang sudah ada di treasury on-chain** agar deployer bisa 1–2 tx admin lagi — **tanpa minta Anda transfer lagi**.

### Apakah add custom token menghapus SCAM?

**Tidak.**

| Aksi | Efek |
|------|------|
| Add custom token (minter `EQCbaUJqi…`) | Anda **lihat** saldo PLX di wallet |
| Label **SCAM** / `blacklist` | Hilang hanya setelah **merge PR ton-assets** + sinkron TonAPI |

---

## Satu-satunya jalur resmi (gratis)

Menurut [Tonkeeper — Token verification](https://tonkeeper.helpscoutdocs.com/article/127-tokennftverification):

1. Fork `tonkeeper/ton-assets`
2. Tambah `jettons/PLX.yaml` (metadata benar, image HTTPS langsung)
3. Pull request → **review & merge** oleh tim Tonkeeper
4. Tunggu cache wallet ~15–60 menit setelah merge

**Tidak ada** API lokal, TON Console, atau Ston.fi yang mengganti langkah ini untuk label SCAM di Tonkeeper.

---

## Status Phalanx (2026-06-03)

| Item | Status |
|------|--------|
| PR | [#5468](https://github.com/tonkeeper/ton-assets/pull/5468) — **OPEN** (antrian banyak PR) |
| TonAPI | `verification: blacklist` |
| `admin.is_scam` | **false** |
| PLX on-chain | 1B, distribusi benar |
| Biaya verifikasi Tonkeeper | **Gratis** — jangan bayar siapa pun untuk “percepat PR” |

---

## Yang sudah / sedang dilakukan (otomatis ops)

- [x] PR #5468 + `jettons/PLX.yaml` (fork `KelvinHernata:add-plx-mainnet-jetton`)
- [x] PR #5468 tetap OPEN (satu komentar awal di thread; **komentar follow-up pribadi dihapus** atas permintaan operator)
- [x] Issue #5475 **ditutup**
- [ ] Verifikasi berikutnya: PR baru dari org **`phalanx-foundation`** (bukan akun pribadi) — lihat [`POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md`](POST-MVP-ECOSYSTEM-AND-FUNDING-PLAN.md)
- [ ] Eskalasi tanpa jejak pribadi: [@tonkeeper](https://t.me/tonkeeper) — [`TONKEEPER-TELEGRAM-ESCALATION.md`](TONKEEPER-TELEGRAM-ESCALATION.md)

**Yang tidak bisa agent lakukan:** merge PR (hanya maintainer Tonkeeper).

---

## Setelah merge — cek sukses

```bash
curl -s "https://tonapi.io/v2/jettons/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS" | jq .verification
# Harus: "whitelist"
```

Tonkeeper: import minter → **tanpa** label SCAM.

---

## Jangan LP dulu (lindungi modal)

Selama `verification` = **`blacklist`**, **jangan** tambah likuiditas Ston.fi — LP tidak menghapus SCAM dan Anda bisa rugi reputasi + TON di pool. Detail: [`AKUNTABILITAS-SCAM-DAN-LP.md`](AKUNTABILITAS-SCAM-DAN-LP.md).

## Bukan solusi SCAM

| Bukan | Kenapa |
|-------|--------|
| Add custom token saja | Hanya tampilan saldo |
| Top-up 5 TON lagi | Deploy sudah selesai |
| Redeploy minter | Supply sudah di kontrak live |
| Bayar “fast verify” | Penipuan — verifikasi resmi gratis |
| LP sebelum whitelist | Harga ≠ verifikasi; risiko rugi 2× |

---

## Kontak eskalasi (urutan)

1. **PR #5468** — semua bukti & dialog di sini (wajib)  
2. **Telegram [@tonkeeper](https://t.me/tonkeeper)** — bot support resmi, pesan siap kirim: [`TONKEEPER-TELEGRAM-ESCALATION.md`](TONKEEPER-TELEGRAM-ESCALATION.md)  
3. **support@tonkeeper.com** — email: [`TONKEEPER-EMAIL-ESCALATION.md`](TONKEEPER-EMAIL-ESCALATION.md)  
4. **Issue [#5475](https://github.com/tonkeeper/ton-assets/issues/5475)** — link ke PR  

---

## Untuk investor (sementara SCAM belum hilang)

Gunakan **Tonviewer** (tanpa label SCAM di explorer):

- Minter: https://tonviewer.com/EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS  
- Treasury: https://tonviewer.com/EQBBlAF4yz12NbrbKXYfGA1OsZzWFpkRj-TU6ciuYjBjK1aX  

Lihat [`STATUS-MAINNET.md`](STATUS-MAINNET.md).
