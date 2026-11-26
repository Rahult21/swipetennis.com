# Cloudflare API and automatic D1 migrations

## Quick Cup

**Court → Quick Cup** creates a four-player lobby. Share its eight-character code or `https://swipetennis.com/cup/CODE`. The website opens `swipetennis://cup/CODE` in an already-installed iPhone/iPad app. Apple sign-in is required; the app is not on the App Store and invites do not install it.

Friends join and mark themselves ready. Only the host starts the cup. The shuffled draw locks at start and open slots receive clearly labeled AI players at the selected Easy/Medium/Hard level, initially the host's practice preference. This is in-game difficulty, independent of ST ranking. Bot styles vary, but level stays fixed. Bot-only matches are labeled simulated. Semifinals feed one final; matches are first to seven points, win by two. Powers are disabled, and cups do not affect Coachability; played human matches update ST ranking.

`CUPS` is a SQLite-backed Durable Object binding. The existing Git-connected deployment applies its configuration and class migration. `0003_quick_cups.sql` adds the account/cup index to D1. No new secrets or manual production commands are required. If the provider rejects the binding or migration, correct the existing build token's Worker deployment permissions and rebuild the same GitHub commit; do not deploy locally.

Authenticated endpoints are `GET/POST /api/cups`, `GET /api/cups/CODE`, `POST /api/cups/CODE/{join,ready,start,leave}`, and WebSocket `/api/cups/CODE/matches/{semi-1,semi-2,final}/socket`. Public `/api/cups/capabilities` identifies protocol version 2 with `stRankings: true`. The Worker verifies the existing session before forwarding identity to a private room. The room serializes roster/results and enforces membership, host-only starting, capacity, readiness, score progression, snapshot ownership, message sizes and message rates. Creation and result delivery can be retried safely.

The first human in each match runs the native simulation. The other sends typed controls and receives 20 Hz snapshots. Both see their own baseline at the bottom. The room checkpoints each scored point and periodically saves live state. This is casual peer-authoritative play, not server-simulated anti-cheat. ST is a social skill estimate on top of this peer-authoritative game. Host latency affects the remote player; authoritative anti-cheat and cross-region competitive validation remain future work. Missing players have 60 seconds to join or reconnect. One missing player forfeits; two missing players cancel the cup. Cups expire after 24 hours; results and account indexes are removed 30 days later. Account deletion anonymizes shared bracket entries and forfeits unfinished participation.

After starting the local Worker and applying local migrations, run `npm run test:api` and `npm run test:cups`. The cup integration suite creates fictional local accounts and exercises four-human/mixed cups through real WebSockets, including reconnect checkpoints and final results. Native UI tests may use simulator-only environment variables `SWIPETENNIS_LOCAL_TEST_URL=http://127.0.0.1:8788/api/`, `SWIPETENNIS_LOCAL_TEST_USER`, and `SWIPETENNIS_LOCAL_TEST_TOKEN` with a matching seeded local session. These overrides are compiled out of physical-device builds; production authentication is unchanged.

The native iOS app calls **https://swipetennis.com/api/**. The existing **swipetennis-com** Worker serves the website assets and the app's JSON API. Production configuration lives in the repository-root `wrangler.jsonc`.

- GitHub repository: `Rahult21/swipetennis.com`, branch `main`
- D1 database: `swipetennisdb`
- Database ID: `179ff7a4-c542-4499-b065-b038543465ae`
- D1 binding: `DB`
- Apple audience: `com.swipetennis.app`

## ST ranking

Migration `0004_st_rankings.sql` creates account ratings and idempotent match receipts. Existing and new accounts begin at **ST 4t**, within **1–10**. `t` means tentative until five completed online human matches. `/me` and Apple sign-in return `stRating` (points, humanMatches, wins, tentative); cup players carry a rating snapshot and completed human matches carry before/after `ratingChanges`.

Only new-version cups with two authenticated humans who both readied up can rate a normally completed tiebreak. AI, simulated matches, practice, manually scored matches, walkovers, forfeits, disconnects, and old cups never affect ST or its human W/L record. Ratings do not change movement or shot power.

For rating R versus opponent O, expected result is `clamp(0.5 + (R-O)/10, 0.1, 0.9)`. Update by `K × (win - expected)`, with K=0.8 for tentative players, otherwise 0.4. Round to two decimals and clamp to 1–10. Equal-rating changes are ±0.4 tentative or ±0.2 established. Both pre-match ratings are read and updated in one D1 batch transaction. A unique cup/match receipt prevents retries from double-counting or overwriting later results. The durable room saves a finished match before settlement and retries pending receipts after failures; rating receipts survive ordinary cup expiry. Account deletion removes that account's rating and associated receipts.

ST is separate from Coachability. Bot difficulty remains the host's fixed Easy/Medium/Hard selection; automatic ST matchmaking and ST-calibrated bots are not implemented.

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

- [API health](https://swipetennis.com/api/health) returns `{"ok":true,"rulesVersion":3}`.
- [Point standings](https://swipetennis.com/api/leaderboard?metric=point) returns ten clearly marked example entries before real results exist. This request also verifies that D1 tables are available.
- Open SwipeTennis on the iPhone, choose **Play & practice**, then complete **Sign in with Apple**. The first sign-in creates the private Apple subject record in D1. Completing a point sends its Coachability events. Complete a game/set to rank in those categories.

Apple's identity token is checked against Apple's public keys, issuer, app audience, expiry and a single-use server nonce. No Apple private key is required for this token-validation flow.

## Data and rankings

- Public entries contain a random app user ID, masked email and personal-best score. Only the first five characters of the username before `@` are visible (for example `rahul@example.com` → `rahul`); the full email is not stored. Apple relay addresses work.
- Migration `0002_email_username_masks.sql` hides the old domain suffix for existing accounts. Because full emails were never stored, the first-five-character name is refreshed at the next verified Apple sign-in. Scores and account IDs are preserved.
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

The five-character name change needs no schema migration: `email_mask` stores the new prefix on verified Apple sign-in. Existing public rows show only their already-retained prefix until refresh; no suffix or email domain is exposed.
