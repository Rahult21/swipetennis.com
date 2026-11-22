# Cloudflare API and automatic D1 migrations

The native iOS app calls **https://swipetennis.com/api/**. The existing **swipetennis-com** Worker serves the website assets and the app's JSON API. Production configuration lives in the repository-root `wrangler.jsonc`.

- GitHub repository: `Rahult21/swipetennis.com`, branch `main`
- D1 database: `swipetennisdb`
- Database ID: `179ff7a4-c542-4499-b065-b038543465ae`
- D1 binding: `DB`
- Apple audience: `com.swipetennis.app`

## GitHub → Cloudflare → D1

This follows SantaAgents' existing migration-before-deployment pattern. In Cloudflare > Workers & Pages > **swipetennis-com** > Settings > Build, use:

| Setting | Value |
| --- | --- |
| Repository / production branch | `Rahult21/swipetennis.com` / `main` |
| Root directory | Repository root (leave blank) |
| Build command | `npm run build` |
| Deploy command | `npx wrangler deploy` |

Cloudflare installs the repository dependencies. The build compiles the existing website, then runs `db:migrate:ci`. That script applies pending D1 migrations **only when Cloudflare sets `WORKERS_CI=1` and `WORKERS_CI_BRANCH=main`**. Local builds and other branches skip remote migrations. A failed migration fails the build, so the new Worker is not published against an incomplete schema. A migration that succeeds remains applied even if a later deployment fails; keep future migrations backward compatible.

`d1_migrations` records which SQL files have run. The first production build creates the app tables and indexes. Later builds apply only newly added migrations. Add new numbered SQL files under `apple/Backend/migrations`; do not edit an already-applied migration. No manual SQL paste is required.

The existing build token needs **Account → D1 → Edit** in addition to its Worker deployment permissions. If a build reports a D1 authorization error, update its Cloudflare build token and retry the build. No API token belongs in this repository or the iPhone app. Production migrations must never be added to an unguarded preview build command.

A separate API Worker or subdomain is not required. API requests use `/api/*`; other requests continue to use the existing website's assets. The native app remains SwiftUI/SpriteKit, with no website embedded in it.

## Verify the deployed result

- [API health](https://swipetennis.com/api/health) returns `{"ok":true,"rulesVersion":2}`.
- [Point standings](https://swipetennis.com/api/leaderboard?metric=point) returns ten clearly marked example entries before real results exist. This request also verifies that D1 tables are available.
- Open SwipeTennis on the iPhone, choose **Play & practice**, then complete **Sign in with Apple**. The first sign-in creates the private Apple subject record in D1. Completing a point sends its Coachability events. Complete a game/set to rank in those categories.

Apple's identity token is checked against Apple's public keys, issuer, app audience, expiry and a single-use server nonce. No Apple private key is required for this token-validation flow.

## Data and rankings

- Public entries contain a random app user ID, masked email and personal-best score. Only the first two and last character of the username before `@` are visible (for example `rahul@example.com` → `ra•••l`); the full email is not stored. Apple relay addresses work.
- Migration `0002_email_username_masks.sql` hides the old domain suffix for existing accounts. Because full emails were never stored, the correct username suffix is refreshed at the next verified Apple sign-in. Scores and account IDs are preserved.
- Rule 7 records recovery-and-split consistency once per point (opportunity `0`): +2 if every eligible baseline exchange qualifies, otherwise −1. Intentional net approaches are exempt; points without an eligible exchange score neither. Repeated rule-7 entries or nonzero opportunity IDs are rejected.
- Points are recalculated server-side as +2 / −1 from distinct rule opportunities. Repeated uploads are idempotent, saved results cannot be edited, and a session belongs to one account.
- Point winners are checked against tennis scoring before completed games or sets can rank. Optional standalone tiebreaks count only in the point category.
- The client reports coaching outcomes; this is not authoritative server replay or App Attest anti-cheat enforcement.
- Bearer tokens are hashed in D1 and held in the iOS Keychain, expiring after 30 days. The app checks Apple credential state, supports sign-out and app-account deletion, and queues offline results per account.
- Deleting an app account removes its user, tokens, sessions and scores. Apple's authorization association can separately be removed in Apple Account settings.
- Example scores are generated response fixtures and are never stored as real accounts.

## Local validation

With Node.js 22 or newer installed, from the repository root:

```sh
npm ci
npm run test:api
npm run build
npm run db:migrate:local
npx wrangler dev --local --port 8788
# In another terminal:
node apple/Backend/tests/integration.mjs
```

`integration.mjs` only accepts a localhost Worker URL, seeds fictional users into local D1, tests API authorization, privacy, personal bests, duplicate delivery, tennis scoring, account ownership, sign-out and deletion, then removes its fixtures. It never writes to remote D1. The `wrangler.sh` helper locates Node on this Mac and forwards commands to the root configuration.

For a manually authorized production deployment, `npm run deploy` also applies pending remote migrations before invoking Wrangler. Git-connected Cloudflare deployment is the normal workflow.

References: [Workers Builds configuration](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/), [D1 migrations](https://developers.cloudflare.com/d1/reference/migrations/), [Apple token validation](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).
