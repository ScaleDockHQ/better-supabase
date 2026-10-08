# instant-nav rig: Next.js example

- BUILD: `pnpm --filter better-supabase build` once (the example imports its
  `dist`), then Playwright's `webServer` runs `node e2e/serve.ts`: one
  `next build`, then `next start` on 3100 and, once that answers, a second
  `next start` on 3101 with `BS_FETCH_DELAY_MS=3000`, where every Supabase
  request from the server (`src/lib/latency.ts`) waits 3 s.
- EXPOSE: `EXPOSE_TESTING_API=1`, which `webServer` sets for the build and
  `next start`. It turns on `experimental.exposeTestingApiInProductionBuild`
  in `next.config.ts` and `debug.enabled` in `src/lib/supabase/server.ts`
  (the database budget); no other build sets it.
- RUN: `pnpm --filter @better-supabase/example-nextjs test:e2e` resets the
  local stack (`pnpm supabase:reset`), then runs `playwright test`. Use
  `pnpm exec playwright test e2e/<file>` from `apps/examples/nextjs` to run one
  contract without a reset; the flows spec creates users and invitations, so
  reset before running it twice. `baseURL` is `http://127.0.0.1:3100`; the
  `latency` project (`--project=latency`, only `latency.spec.ts`) uses 3101.
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
  - Settings tabs, for each user: a click from one tab to the next commits
    the "Settings" heading and the tab's content under the lock, through
    Security (the two-factor status and the connected agents) and back to
    Profile; Audit log is absent for members (`settings.spec.ts`). The spec
    signs in fresh, because Security asks the Auth server, which refuses a
    saved session once the flows spec has signed that user out everywhere.
  - Flows: sign in and out, a wrong password, sign-up without an
    organization, password reset through Mailpit, the organization switch
    without a reload, the language switch, the theme before first paint, and
    invite, sign-up and accept (`flows.spec.ts`).
  - Latency, on 3101 (`latency.spec.ts`, timed from the navigation until the
    locator is visible; page loads wait for `commit`, not `load`, because
    `load` waits for the whole stream): `/login` under 1 s; a cold dashboard
    `h1` under 1.5 s and its summary after 2.5 s or more; Customers 2.5 s or
    more on a full load, under 1 s on the next sidebar visit and 2.5 s or
    more again on reload; the plan grid under 1 s on reload and for another
    user while their subscription takes 2.5 s or more; a customer search 2.5
    s or more the first time (`page.route()` delays the browser's
    `/rest/v1/customers` calls) and under 1 s for the same search again.
- LOOP: local build, start and test through `webServer`, edit, repeat. The
  agent can run every step.
- LIVENESS: n/a; local build and start.
- WALLS: a fresh worktree has no `packages/better-supabase/dist`, so the build
  fails with "Module not found: better-supabase/..." until the package is
  built. In a sandbox, set `PLAYWRIGHT_BROWSERS_PATH` to the user's
  `ms-playwright` cache, or run `pnpm exec playwright install chromium`.
  A database budget only works on a navigation that reaches the server: one
  served from the client cache has no `x-bs-request-id` response and fails.
- TIMINGS (one local run, 3 s delay): login 27 ms; dashboard shell 62 ms,
  summary 3397 ms; Customers full load 3333 ms, warm visit 40 ms, reload
  3356 ms; search 3323 ms, again 14 ms; plans 63 ms on the first load (a
  sidebar prefetch on the same server had already filled the shared cache),
  76 ms on reload and 63 ms for another user, whose subscription took
  3403 ms. All seven settings tabs, clicked in a row, 864 to 964 ms per user.
- DIFFERENTIAL: with the two-factor card and the connected agents card
  loading their data in a client `useEffect` (the code before
  `security-queries.ts`), the settings contract is RED for every user at
  Security ("getByTestId('mfa-status') was not visible under the instant()
  lock"); the cached server reads turn it GREEN. Replacing
  `"use cache: private"` and `bs.cached()` in
  `getCustomers` with `bs.context()` turns both Customers list contracts RED
  ("not in the prefetched UI"); restoring it turns them GREEN. Removing only
  the directive fails the render, because `bs.cached()` calls `cacheLife()`.
  With the delay, removing `"use cache"` from `getPlans` turns the shared
  plan catalog contract RED (the reload waits for the database); restoring
  it turns it GREEN.
