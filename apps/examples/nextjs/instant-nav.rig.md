# instant-nav rig: Next.js example

- BUILD: `pnpm --filter better-supabase build` once (the example imports its
  `dist`), then Playwright's `webServer` runs `next build && next start -p 3100`.
- EXPOSE: `EXPOSE_TESTING_API=1`, which `webServer` sets for the build and
  `next start`. It turns on `experimental.exposeTestingApiInProductionBuild`
  in `next.config.ts` and `debug.enabled` in `src/lib/supabase/server.ts`
  (the database budget); no other build sets it.
- RUN: `pnpm --filter @better-supabase/example-nextjs test:e2e` resets the
  local stack (`pnpm supabase:reset`), then runs `playwright test`. Use
  `pnpm exec playwright test e2e/<file>` from `apps/examples/nextjs` to run one
  contract without a reset; the flows spec creates users and invitations, so
  reset before running it twice. `baseURL` is `http://127.0.0.1:3100`.
- TEST USERS (`e2e/users.ts`, password `password123`, from `supabase/seed.sql`):
  `admin@acme.test` (owner of Acme, member of Globex), `member@acme.test`
  (member of Acme) and `owner@globex.test` (owner of Globex). The setup
  project signs each in through `/en/login` and saves `e2e/.auth/<user>.json`.
  Mail (password reset) is read from Mailpit on port 55424.
- DRIFT: the role and organization (the menu per user is the `routes` table
  in `pages.spec.ts`), the seed data (Acme has "Road Runner Inc", Globex has
  "Initech", the beta flag is on for Acme only), the active organization
  (stored per user: the org switch spec switches back to Acme) and token
  expiry (an expired access token renders signed out, because prefetches
  never refresh). The suite signs in fresh on every run.
- HIDDEN COPIES: Cache Components keeps routes you left in a hidden
  `<Activity>`, and a streamed Suspense boundary sits in a hidden `<div>`
  before React swaps it in. Locate by role, or through `visibleTestId`,
  `visibleText` and `field` in `e2e/nav.ts`.
- CONTRACTS (`expectInstant` from `better-supabase/testing`, except the
  initial loads, which call `instant()` directly):
  - Every menu page, for each user in `en` and `nl`: a sidebar click commits
    the `h1` under the lock; links a user can't see are absent; members are
    redirected away from `/settings/audit`; Globex gets a 404 for `/beta`
    (`pages.spec.ts`).
  - Initial load of the dashboard: `h1` and the busy skeletons under the lock,
    no organization name; a customer page's back link; `/login`, `/signup`
    and `/forgot-password` fully static (`initial-load.spec.ts`).
  - Click "Customers": `h1`, "Road Runner Inc" and the status facets from the
    per-session App Shell, within 8 calls in 2 waves; a row click commits the
    detail (the row link prefetches, because `params` content can't be in the
    shared shell); members get the read-only view; Globex sees only Initech
    (`customers.spec.ts`).
  - Flows: sign in and out, a wrong password, sign-up without an
    organization, password reset through Mailpit, the organization switch
    without a reload, the language switch, the theme before first paint, and
    invite, sign-up and accept (`flows.spec.ts`).
- LOOP: local build, start and test through `webServer`, edit, repeat. The
  agent can run every step.
- LIVENESS: n/a; local build and start.
- WALLS: a fresh worktree has no `packages/better-supabase/dist`, so the build
  fails with "Module not found: better-supabase/..." until the package is
  built. In a sandbox, set `PLAYWRIGHT_BROWSERS_PATH` to the user's
  `ms-playwright` cache, or run `pnpm exec playwright install chromium`.
  A database budget only works on a navigation that reaches the server: one
  served from the client cache has no `x-bs-request-id` response and fails.
- DIFFERENTIAL: replacing `"use cache: private"` and `bs.cached()` in
  `getCustomers` with `bs.context()` turns both Customers list contracts RED
  ("not in the prefetched UI"); restoring it turns them GREEN. Removing only
  the directive fails the render, because `bs.cached()` calls `cacheLife()`.
