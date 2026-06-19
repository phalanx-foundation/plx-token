# Mainnet Go / No-Go (gate sebelum announce investor)

Gunakan checklist ini **sebelum** demo investor, press, atau kampanye retail. Satu item **FAIL** = **No-Go**.

## A. On-chain (wajib PASS)

| # | Cek | Cara | PASS |
|---|-----|------|------|
| A1 | Supply 1B PLX | Tonviewer / `audit-mainnet-plx` | total_supply sesuai |
| A2 | Distribusi genesis | Script audit | LP 400M, Treasury 250M, Community 200M, Vesting 100M, Marketing 50M |
| A3 | Deployer 0 PLX | TonAPI account jettons | 0 PLX (normal) |
| A4 | Metadata image HTTPS | GET `https://plx.foundation/plx-logo.png` | 200 OK |

## B. Registry & wallet UX (wajib PASS untuk announce)

| # | Cek | Cara | PASS |
|---|-----|------|------|
| B1 | TonAPI verification | `GET /v2/jettons/{minter}` | **`whitelist`** (bukan `blacklist`) |
| B2 | Tonkeeper tanpa SCAM | Import minter di device nyata | Tidak ada label SCAM |
| B3 | ton-assets PR | GitHub #5468 | **Merged** ke `tonkeeper/ton-assets` |
| B4 | Handoff wallet | Operator punya backup mnemonic semua `plx-*-mainnet` | Dokumentasi + vault offline |

## C. Operasi (wajib sebelum “final”)

| # | Cek | PASS |
|---|-----|------|
| C1 | `acton test` hijau di commit yang di-deploy | 72+ tests |
| C2 | Deploy log tersimpan | `.deploy-mainnet.log` di server |
| C3 | Keputusan drop admin | `drop-admin` dijalankan ATAU alasan tertulis menunda |
| C4 | TON Console / verifikasi kontrak | Terjadwal (tidak mengganti B1–B3) |

## D. Sengaja di luar gate ini

- Ston.fi LP (likuiditas retail)
- Web toolkit production-ready
- Ubuntu API + Cloudflare Pages deploy

## Perintah audit

```powershell
# Windows (repo root)
powershell -File .scripts/ops/audit-mainnet-plx.ps1
```

```bash
# Ubuntu deploy server
cd ~/projects/plx-acton
export TONAPI_KEY=...   # optional
bash .scripts/ops/audit-mainnet-plx.sh
bash .scripts/ops/list-mainnet-wallets.sh
```

## Keputusan

| Hasil | Tindakan |
|-------|----------|
| A PASS, B FAIL | **No-Go announce** — fokus Tonkeeper + handoff wallet |
| A FAIL | Insiden kontrak — eskalasi dev + jangan mint/drop tanpa analisis |
| A+B PASS | Go untuk demo terbatas; LP/web tetap roadmap terpisah |

**Status Phalanx (2026-06-03):** A PASS, **B FAIL** (`verification: blacklist`, PR #5468 OPEN).
