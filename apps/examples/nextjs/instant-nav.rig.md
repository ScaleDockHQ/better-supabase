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
  contract without a reset. `baseURL` is `http://127.0.0.1:3100`.
- TEST USER: `admin@acme.test` (role `admin`) and `member@acme.test` (role
  `member`), password `password123`, from `supabase/seed.sql`. The setup
  project signs in through `/login` and saves `e2e/.auth/<user>.json`.
- DRIFT: the role (members see five fewer menu items and are redirected away
  from admin pages), the seed data ("Road Runner Inc" must exist for org 1),
  and token expiry (an expired access token renders signed out, because
  prefetches never refresh). The suite signs in fresh on every run.
- CONTRACTS (the click specs use `expectInstant` from
  `better-supabase/testing`; the dashboard checks an attribute, so it calls
  `instant()` directly):
  - Initial load of `/`: `h1` "Dashboard" and the sidebar skeleton under the
    lock; `workspace-summary` after release (`dashboard.spec.ts`).
  - Click "Customers" from `/`: `h1`, "Road Runner Inc" and `similar-notes`
    from the per-session App Shell, within 8 calls in 2 waves
    (`customers.spec.ts`), and for the member the read-only notice
    (`member.spec.ts`).
  - Click "Reports" and "Billing": the permission-gated panels from the
    cached session (`gated-pages.spec.ts`).
  - Click "Inbox": `h1` under the lock; `unread-summary` only after release,
    because the count is read per request (`inbox.spec.ts`).
  - Creating a customer shows it on the next visit and after a reload.
- LOOP: local build, start and test through `webServer`, edit, repeat. The
  agent can run every step.
- LIVENESS: n/a; local build and start.
- WALLS: a fresh worktree has no `packages/better-supabase/dist`, so the build
  fails with "Module not found: better-supabase/..." until the package is
  built. In a sandbox, set `PLAYWRIGHT_BROWSERS_PATH` to the user's
  `ms-playwright` cache, or run `pnpm exec playwright install chromium`.
- DIFFERENTIAL: removing `'use cache: private'` from `getCustomers` turns
  both Customers contracts RED (the heading commits, the rows never do);
  restoring it turns them GREEN. Lowering `maxCalls` in `customers.spec.ts`
  below 4 turns the App Shell contract RED with the render's calls and
  tables.
