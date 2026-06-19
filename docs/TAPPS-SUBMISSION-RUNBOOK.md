# tApps Center + TON app platform submission runbook

Phalanx listing targets: **tApps Center**, **tonscan.org/apps**, optional **TON Builders** analytics.

| Platform | URL | Bot / form |
|----------|-----|------------|
| tApps Center | https://tapps.center/ | [@app_moderation_bot](https://t.me/app_moderation_bot) |
| tonscan apps | https://tonscan.org/apps | [@SubmitAppBot](https://t.me/SubmitAppBot) |
| Analytics token | https://builders.ton.org | Analytics tab → SDK token |
| Support | — | [@tapps_center_moderation](https://t.me/tapps_center_moderation) |

---

## DApp vs Web vs PLX App (Phalanx)

| Term | What it is | Phalanx |
|------|-----------|---------|
| **Web** | Regular website in a browser | [plx.foundation](https://plx.foundation) — landing, docs, pricing |
| **DApp** | Web app + on-chain interaction (wallet, contracts) | `/build`, `/dashboard`, `/earn`, TonConnect — same codebase, not a separate app |
| **PLX App** | Full app on its own subdomain + inside Telegram WebView | [app.plx.foundation](https://app.plx.foundation) — Formation quests, bottom-tab navigation, opened from [@phalanxfoundationbot](https://t.me/phalanxfoundationbot) |

What is registered with **tApps Center** = **bot + PLX App URL** (`app.plx.foundation`), not the entire website.

---

## Register on builders.ton.org (Analytics token)

Use the **product** name, not only the token ticker:

| Field | Recommended value |
|-------|-------------------|
| **Project name** | `PLX App` |
| **Short description** | `Audited jetton deploy toolkit on TON with Formation earn campaigns and PLX utility token.` |
| **Link to app** | `https://app.plx.foundation/` |
| **Telegram channel** | `https://t.me/phalanxfoundation` |
| **GitHub** | `https://github.com/phalanx-foundation/plx-token` |

Notes:

- **PLX Token** = jetton ticker; **PLX Foundation** = org brand; **PLX App** = the Telegram Mini App registered in tApps.
- Analytics identifier (e.g. `plx_app`) can differ from display name — keep it stable for `@app_moderation_bot`.
- Private repo `plx-toolkit` is backend only; public `plx-token` is correct for GitHub field.

---

## Bot profile "Open App" vs chat "Open PLX App"

| Button | Where | Opens | Config |
|--------|-------|-------|--------|
| **Open App** | Bot profile (top) | Whatever BotFather **Main Mini App URL** is set to | BotFather → Configure Mini App — **must be** `https://app.plx.foundation/` |
| **Open PLX App** | Menu inside chat (☰ / bottom) | `https://app.plx.foundation/` | `setChatMenuButton` via API |
| **Open PLX App** | Inline button after `/start` | `app.plx.foundation` in WebView | API webhook `reply_markup` |

Production `/start` text is handled by **Ubuntu API** (`api/routes/telegram.py` at `api.plx.foundation`), not the Cloudflare `toolkit-staging/bot` worker.

---

## Demo video — what is expected?

tApps does **not** have an official template, but reviewers expect **2–3 minute screen recording** showing real flows (not slides):

1. **0:00–0:20** — Open [@phalanxfoundationbot](https://t.me/phalanxfoundationbot) → `/start` → tap **Open PLX App** (menu or inline button).
2. **0:20–1:00** — PLX App fully loaded: bottom tab bar visible, quest panel, no infinite loading; horizontal swipe does not expose white gap.
3. **1:00–1:40** — **TonConnect**: connect wallet → show lock/claim or swap link (TON-only Web3 feature).
4. **1:40–2:20** — One quest flow: verify Telegram join or view campaign countdown / earn progress.
5. **2:20–2:45** — Deep link to `/build` or Deploy button (optional, shows toolkit).
6. **2:45–3:00** — Close with logo + `plx.foundation`, channel [@phalanxfoundation](https://t.me/phalanxfoundation).

**Format:** MP4 or MOV, 1080p, **no watermark**, audio optional (English voiceover recommended).  
**Upload:** when submitting via `@app_moderation_bot` (demo / link field) or re-send if moderator requests.

---

## Two Telegram SDKs (don't confuse)

| SDK | Function | Phalanx status |
|-----|----------|----------------|
| **Telegram WebApp SDK** (`telegram-web-app.js`) | Native UI: expand, header color, close, swipe lock | ✅ global in `layout.tsx`, active via `AppBootstrap` |
| **Telegram Mini Apps Analytics SDK** (`@telegram-apps/analytics`) | Anonymous events for tApps ranking; **required for listing** | ✅ code present; needs token from TON Builders |

Analytics token:

1. https://builders.ton.org → login Telegram → project PLX App
2. Tab **Analytics** → bot URL + domain `app.plx.foundation`
3. Copy token → env:
   - `NEXT_PUBLIC_TG_ANALYTICS_TOKEN`
   - `NEXT_PUBLIC_TG_ANALYTICS_APP_NAME` (identifier, e.g. `plx_app`)

Set in **Cloudflare Pages** (prod web) then redeploy.

---

## Technical checklist (repo)

| # | Item | How to verify |
|---|------|---------------|
| 1 | Main Mini App URL | BotFather → `@phalanxfoundationbot` → Configure Mini App → `https://app.plx.foundation/` |
| 2 | Menu button web_app | `cd toolkit-staging/bot && npm run configure-tapps` |
| 3 | `/start` English + PLX App button | Deploy bot worker, test in Telegram |
| 4 | Analytics SDK | `@DataChief_bot` → "Last record" recent after opening PLX App |
| 5 | Privacy + Terms | https://plx.foundation/terms · https://plx.foundation/security |
| 6 | Demo video | Record the script above |
| 7 | 6 screenshots | PLX App + bot + swap/markets; portrait 9:16 ratio recommended |

Run readiness check:

```powershell
powershell -File "D:\DATA TOOLS\PLX-ACTON\scripts\tapps-readiness-check.ps1"
```

---

## Submit to tApps Center

1. Ensure checklist above is green.
2. Open [@app_moderation_bot](https://t.me/app_moderation_bot) → **Submit Your App**.
3. Fill in:
   - **Bot:** `@phalanxfoundationbot`
   - **Mini App URL:** `https://app.plx.foundation/`
   - **Analytics app name:** same as `NEXT_PUBLIC_TG_ANALYTICS_APP_NAME`
   - **Name:** PLX App
   - **Tagline:** Deploy jettons & earn on TON — inside Telegram
   - **Description:** English, 2–3 paragraphs (toolkit + PLX + Formation quests)
   - **Category:** Jettons / Services (choose most fitting)
   - **Screenshots:** 6 slots
   - **Demo:** Drive/YouTube unlisted link or file upload if bot requests
4. Wait **3–8 days**; respond to moderator feedback promptly.

---

## Submit to tonscan.org/apps

1. [@SubmitAppBot](https://t.me/SubmitAppBot)
2. URL: `https://app.plx.foundation/` (or homepage if bot requests "main app")
3. Icon: `https://plx.foundation/plx-logo.png`
4. English description + bot & GitHub links

---

## After approval

- Update [`TOKEN-LISTING-INDEX-MATRIX.md`](TOKEN-LISTING-INDEX-MATRIX.md) rows D2–D3 → **LIVE** + evidence URL
- Light promotion in channel; get 10–15 early users to open from catalog (helps trending)

---

## Blockers that cannot be automated from repo

| Blocker | Owner |
|---------|-------|
| Tonkeeper whitelist (ton-assets PR) | TON maintainer merge |
| Analytics token TON Builders | Login Telegram org |
| Submit @app_moderation_bot | Human in Telegram |
| Record demo video | Human screen record |
| BotFather Main Mini App URL = `https://app.plx.foundation/` | Manual BotFather step |
