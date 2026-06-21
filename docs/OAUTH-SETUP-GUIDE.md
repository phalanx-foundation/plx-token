# OAuth Setup — Google + GitHub login for `plx.foundation` clients

**Audience:** Phalanx Foundation operator (you).
**Goal:** enable end-user clients to sign in to the Phalanx Toolkit
(`plx.foundation`) using their Google or GitHub account, so they can configure
and deploy their own jetton via the `/build` flow.

The website code is already wired:

- `auth.ts` registers Google + GitHub providers **only if their env vars are
  set** — the live site won't crash without them; OAuth buttons simply fail
  gracefully until env is populated.
- `/auth/signin` already shows Google + GitHub buttons in the UI.
- `/build` is auth-protected — unauthenticated users get 307-redirected to
  `/auth/signin?callbackUrl=/build`.

You need to do three one-time things:

1. Register an OAuth app on **Google Cloud Console** (≈ 5 min).
2. Register an OAuth app on **GitHub Developer Settings** (≈ 2 min).
3. Run `.scripts/ops/set-cf-pages-oauth-env.ps1 -GoogleId ... -GoogleSecret ... -GithubId ... -GithubSecret ...`
   to push them into Cloudflare Pages and trigger a redeploy.

After that, the buttons will work for every client without any additional
manual intervention.

---

## Exact callback URLs you must paste

**Satu OAuth client Google** dipakai untuk web pelanggan **dan** admin dashboard
(`dev.plx.foundation`). Jangan buat client baru — cukup tambah URI kedua ke
client **Phalanx Toolkit (production)** yang sudah ada.

| Provider | Callback URL | Dipakai oleh |
|---|---|---|
| Google | `https://plx.foundation/api/auth/callback/google` | `plx.foundation` (web) |
| Google | `https://dev.plx.foundation/api/auth/callback/google` | `dev.plx.foundation` (admin) |
| GitHub | `https://plx.foundation/api/auth/callback/github` | `plx.foundation` (web saja) |

Authorized JavaScript origins (Google, client yang sama):

- `https://plx.foundation`
- `https://dev.plx.foundation`

These are the URLs the OAuth provider will redirect the browser back to
after the user clicks "Allow". They are **required** to be added to the
provider's allow-list, otherwise sign-in returns a 400 error.

---

## 1. Google OAuth app

1. Open <https://console.cloud.google.com/projectcreate>. Sign in with the
   Google account you want to control the OAuth app (use a Foundation-owned
   account, not a personal one).
2. Project name: `Phalanx Toolkit`. Organization: leave blank or your org.
   Click **Create**, then make sure the new project is selected in the top
   bar.
3. Open <https://console.cloud.google.com/apis/credentials/consent>:
   - User type: **External**. Click **Create**.
   - App name: `Phalanx Toolkit`.
   - User support email: `ops@plx.foundation`.
   - App logo: upload `metadata/logo-512.png` (≤ 1 MB, square).
   - App home page: `https://plx.foundation`.
   - Authorized domains: add `plx.foundation`.
   - Developer contact information: `ops@plx.foundation`.
   - Click **Save and continue** through the next two screens (Scopes —
     leave default `openid`, `email`, `profile`; Test users — skip while in
     test mode, or add the operator email if you want to gate it).
4. Open <https://console.cloud.google.com/apis/credentials> → **Create
   credentials** → **OAuth client ID**:
   - Application type: **Web application**.
   - Name: `Phalanx Toolkit (production)`.
   - Authorized JavaScript origins:
     `https://plx.foundation`, `https://dev.plx.foundation`
   - Authorized redirect URIs (satu client, dua subdomain):
     `https://plx.foundation/api/auth/callback/google`,
     `https://dev.plx.foundation/api/auth/callback/google`
   - Click **Create**.
5. Google shows a modal with the **Client ID** and **Client secret**. Copy
   both — you cannot retrieve the secret again later (you can only rotate it).
   Paste them into 1Password under `Phalanx Foundation / Google OAuth`.
6. (Recommended) Move the consent screen out of "Testing" mode by clicking
   **Publish app** on the OAuth consent screen page, otherwise only test
   users you whitelisted can sign in.

---

## 2. GitHub OAuth app

1. Open <https://github.com/organizations/phalanx-foundation/settings/applications/new>
   to register the OAuth app under the **Foundation org** (not your personal
   account). If you only see your personal account, switch context with the
   org-picker at the top of the page.
   - Application name: `Phalanx Toolkit`.
   - Homepage URL: `https://plx.foundation`.
   - Application description: `Audited TON jetton tokenization toolkit. Sign in to deploy.`.
   - Authorization callback URL:
     `https://plx.foundation/api/auth/callback/github`
   - Enable Device Flow: **off**.
   - Click **Register application**.
2. The app page now shows the **Client ID**. Click **Generate a new client
   secret** and copy it immediately (you won't see it again).
3. Upload an app logo: scroll down on the same page, click **Upload new logo**,
   pick `metadata/logo-512.png`.
4. Paste both values into 1Password under `Phalanx Foundation / GitHub OAuth`.

---

## 3. Push secrets to Cloudflare Pages

From the repo root on Windows:

```powershell
$creds = @{
  GoogleId     = '<paste here>.apps.googleusercontent.com'
  GoogleSecret = '<paste here>'
  GithubId     = '<paste here>'
  GithubSecret = '<paste here>'
}

.\.scripts\ops\set-cf-pages-oauth-env.ps1 @creds
```

The script:

- Reads `CLOUDFLARE_API_TOKEN` from your user environment (already set).
- Patches the production + preview `env_vars` of the `plx-toolkit` Pages
  project, adding the four `AUTH_*` keys as `secret_text`.
- Triggers a redeploy of the latest production deployment so the new env is
  picked up.
- Prints the resulting (redacted) env list at the end.

Re-running the script with new values rotates the secrets — no other action
needed on your part.

---

## How the runtime picks them up

`auth.ts` (in `toolkit-staging/web/`) reads:

```ts
if (process.env.AUTH_GOOGLE_ID && process.env.AUTH_GOOGLE_SECRET) {
  providers.push(Google({ clientId: ..., clientSecret: ... }));
}
if (process.env.AUTH_GITHUB_ID && process.env.AUTH_GITHUB_SECRET) {
  providers.push(GitHub({ clientId: ..., clientSecret: ... }));
}
```

So:

- Both env pairs missing → only "dev credentials" form is functional in dev,
  in production no provider works (the button shows but `/api/auth/...` 404s).
- Only Google set → only Google button works.
- Both pairs set → all three sign-in paths work in dev; only Google + GitHub
  in production (Credentials provider auto-disables when `NODE_ENV=production`).

The Edge runtime config (`/build`, `/dashboard`, `/auth/signin`,
`/api/auth/[...nextauth]`) is already correct for Cloudflare Pages.

---

## What clients see

1. They land on `https://plx.foundation`.
2. They click **Build Token** in the topbar (left of "Sign in").
3. `/build` is protected; they get redirected to
   `https://plx.foundation/auth/signin?callbackUrl=/build`.
4. They click **Continue with Google** (or GitHub).
5. They consent on the provider's page (first time only) and land back on
   `/build` with an active session — ready to fill the jetton config form.

No accounts to manage on our side; we just persist the OAuth subject in the
NextAuth JWT.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Button click → `redirect_uri_mismatch` | Callback URL not whitelisted on the provider | Re-check the exact URL in step 1.4 / 2.1 — paths are case-sensitive |
| `Configuration` error after redirect | Env var typo (e.g. trailing whitespace) | Re-run helper script; values are trimmed automatically |
| Google "Access blocked: this app's request is invalid" | OAuth consent screen still in Testing and user is not whitelisted | Publish the consent screen (step 1.6) |
| GitHub `Bad verification code` | Client secret rotated but env not updated | Re-run helper script with fresh secret |
| Works in production, not preview | Helper sets both production + preview by default; verify with `gh / cloudflare dash` env list | Re-run helper, watch the printed output |

If something else fails, look at the function logs:
`https://dash.cloudflare.com/?to=/$ACCOUNT/pages/view/plx-toolkit` →
**Functions → Logs → /api/auth/[...nextauth]**.
