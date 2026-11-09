# instant-nav rig: apps/examples/nextjs

- BUILD: from `apps/examples/nextjs`, `EXPOSE_TESTING_API=1 pnpm exec next build`, then `pnpm exec next start -p 3100`. Stop whatever is listening on 3100 before the start. The Playwright `webServer` in `playwright.config.ts` builds and starts 3100 and 3101 together.
- EXPOSE: `EXPOSE_TESTING_API=1` during `next build`. `next.config.ts` sets `experimental.exposeTestingApiInProductionBuild` from that variable. Setting it only for `next start` is too late.
- RUN: `BASE_URL=http://localhost:3100 pnpm exec playwright test tests/scale-payload.spec.ts tests/instant.spec.ts tests/loading-sequences.spec.ts` from `apps/examples/nextjs`. The config's `webServer` owns the server when Playwright starts it.
- TEST USER: `admin@acme.test` / `password123` (seed.sql). For the large tenant, load `supabase/seed.scale.sql` after reset (it is not in `[db.seed].sql_paths`). State: locale `en`, Acme as the active organization.
- DRIFT: a reset without `seed.scale.sql` still signs in, and the customers list shows the three seed rows instead of 60,000. Payload bytes then measure the small tenant. The scale file is what the large-tenant numbers use.
- CONTRACTS:
  - `/en` direct load: heading of the dashboard shell is visible before streamed charts.
  - `/en` to `/en/customers` through the Customers link: heading "Customers" is instant, the row "Road Runner Inc" streams (see `tests/loading-sequences.spec.ts` and `tests/instant.spec.ts`).
  - `/en/customers` to the Road Runner Inc link: "All customers" is instant (`tests/instant.spec.ts`).
  - Organization switcher: the switch control is instant; the destination organization's name streams after the click.
- LOOP: local build with `EXPOSE_TESTING_API=1`, start on 3100, run the focused Playwright files, stop the server, edit, repeat. Agent limits: the scale seed and the local stack must already be up; this rig does not start Supabase.
- LIVENESS: n/a; local build and start.
- WALLS: `next build` reads `.env.development.local` from the repo root or the app (see `playwright.config.ts`). Port 3100 is the example app. A second server on 3101 shares the remote cache dir. Without the stack, sign-in never leaves `/en/login`.

## Payload baseline (before the runtime changes)

Measured on the claims shape this branch started from, without a production render (the local stack was not loaded with the scale seed in this pass). Membership bytes are `JSON.stringify` of 150 `{ scope, id, roles: ["member"] }` entries. Permission bytes are one tenant holding 300 `resource.action_NNN` keys in the full bootstrap form. ADR 0523 measured the SQL `membership_claims` array at 14,294 bytes and 9 cookie chunks for 150 memberships on the real hook.

| Measure                                      | Before                                                | After                                               |
| -------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------- |
| Membership claim, 150 entries                | 13,201 bytes (synthetic); 14,294 bytes (ADR 0523 SQL) | 6,199 bytes (`claimFormat: "summary"`, one role)    |
| Cookie chunks at 150 memberships             | 9 (ADR 0523)                                          | not re-measured on a live cookie                    |
| Bootstrap permissions, 300 keys, one tenant  | 6,683 bytes (full)                                    | 6,747 bytes (compact; the key list still dominates) |
| Bootstrap permissions, 300 keys, 150 tenants | 996,192 bytes (full)                                  | 20,604 bytes (compact)                              |
| HTML, Flight, round trips                    | not measured on a production render in this pass      | not measured on a production render in this pass    |
