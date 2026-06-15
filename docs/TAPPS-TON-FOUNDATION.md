# tApps Center + TON Foundation opportunities

For **marketing discoverability** after **PLX App** is listed.

**Full runbook:** [`TAPPS-SUBMISSION-RUNBOOK.md`](TAPPS-SUBMISSION-RUNBOOK.md)

## tApps Center

| Item | Detail |
|------|--------|
| URL | https://tapps.center/ · submit via [@app_moderation_bot](https://t.me/app_moderation_bot) |
| PLX App | `https://app.plx.foundation/` |
| Bot | [@phalanxfoundationbot](https://t.me/phalanxfoundationbot) |
| Needs | Analytics SDK token, English UI, demo video 2–3 min, Terms/Privacy |
| Status | **IN PROGRESS** — SDK + bot commands in repo; submit after analytics token + video |

## tonscan.org apps

| Item | Detail |
|------|--------|
| Bot | https://t.me/SubmitAppBot |
| Needs | Public app URL, description, icon |
| Status | **TODO** — after tApps or in parallel |

## Checklist before apply

- [x] Telegram WebApp SDK global in `layout.tsx` (active via `AppBootstrap`)
- [x] `@telegram-apps/analytics` wired (needs `NEXT_PUBLIC_TG_ANALYTICS_*` in CF Pages)
- [x] Bot `/start` + `/quest` + web_app buttons (deploy bot worker + `npm run configure-tapps`)
- [x] PLX App subdomain `app.plx.foundation` live (DNS CNAME + CF Pages custom domain)
- [x] `X-Robots-Tag: noindex, nofollow` on app subdomain
- [x] Bottom tab bar navigation (native app feel)
- [ ] BotFather **Main Mini App URL** = `https://app.plx.foundation/` (manual step)
- [ ] Analytics token from https://builders.ton.org
- [ ] Demo video (script in runbook)
- [ ] Submit @app_moderation_bot
- [ ] Tonkeeper whitelist (ton-assets PR — wallet UX, not tApps gate)
- [ ] Update matrix D2–D3 in [`TOKEN-LISTING-INDEX-MATRIX.md`](TOKEN-LISTING-INDEX-MATRIX.md)

## TON Console (not a listing)

https://tonconsole.com — TonAPI keys ([`TON-CONSOLE-PLX.md`](TON-CONSOLE-PLX.md)).

## Ops scripts

```powershell
# Prod smoke
powershell -File scripts/tapps-readiness-check.ps1

# Bot menu + commands (needs TELEGRAM_BOT_TOKEN)
cd toolkit-staging/bot
npm run configure-tapps
```
