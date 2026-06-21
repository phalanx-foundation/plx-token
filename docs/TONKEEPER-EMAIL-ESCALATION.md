# Email eskalasi Tonkeeper (salin & kirim)

**Ke:** support@tonkeeper.com  
**Subjek:** URGENT: Remove SCAM label — Phalanx PLX mainnet — PR #5468

---

Hello Tonkeeper team,

We submitted jetton **Phalanx (PLX)** for official listing via GitHub PR **#5468** on `tonkeeper/ton-assets`.

**Problem:** Tonkeeper and TonAPI show **SCAM** / `verification: blacklist` for our legitimate mainnet minter, blocking our launch credibility after a documented genesis deploy.

**Minter (mainnet):** `EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS`  
**PR:** https://github.com/tonkeeper/ton-assets/pull/5468  
**Deployer admin:** `EQBfYLpqRNp4jVvffYb6uckcGVM2S5F1J8pq-pnFsN0anklj` — TonAPI `is_scam: false`

**Genesis deploy transactions:**

- Minter: https://tonscan.org/tx/9b15fddc37e4babda95e2814e7335f9c9fa44b2d5c323a545b4756c103c45e8f  
- TeamVesting: https://tonscan.org/tx/c2a8d82da3bd7fae176325fce3d64294dc3597e91a9c935ebbb8b3ff92de1192  
- PaymentSplitter: https://tonscan.org/tx/bea977805bbb80fef126696aefb2d9081a7c7fa5d3b0916180119e14cec8e07b  

**Supply:** 1,000,000,000 PLX (9 decimals), distributed to five documented wallets + vesting contract (see https://github.com/phalanx-foundation/plx-token/blob/master/docs/MAINNET-DEPLOYMENT-RECORD.md).

**Logo:** https://plx.foundation/plx-logo.png (HTTPS 200)  
**Website:** https://plx.foundation/plx-token

We request:

1. Review and merge PR #5468, or tell us what is missing.  
2. Remove `blacklist` / SCAM status for minter above.  
3. Brief explanation why this minter was blacklisted while `admin.is_scam` is false.

Thank you,  
Phalanx Foundation
