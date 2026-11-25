# One round trip: after numbers and leftovers

Measured the same way as [the before numbers](one-round-trip-before.md): production build, testing API, local stack. Counts are the budget; milliseconds are indicative.

## Summary (pull request text)

Final numbers, taken on the merged tree (`feat/one-round-trip-ship` on top of `main` after #1156), production build, testing API, fresh local stack at the seed tier. Counts are the budget; milliseconds are indicative and vary with machine load.

| Measure (admin, warm render)            | Before            | After                                                                              |
| --------------------------------------- | ----------------- | ---------------------------------------------------------------------------------- |
| Routes measured                         | 190               | 227 with a database call                                                           |
| Database calls, all routes              | 1016              | 566                                                                                |
| Median calls per route                  | 5                 | 2                                                                                  |
| Median waves per route                  | 1                 | 1                                                                                  |
| Median warm render                      | n/a               | 136 ms                                                                             |
| Median client navigation after prefetch | n/a               | 29 ms                                                                              |
| Admin token, cookie, chunks             | 4035 B, 5567 B, 2 | 1494 B, 2179 B, 1                                                                  |
| `/care/[clientId]` calls                | 21                | 18                                                                                 |
| `/customers/[id]` calls                 | 13                | 14 (deferred sections start earlier; `my_permissions` calls went from six to none) |
| `/crm/deals` calls                      | 16                | 13                                                                                 |
| `(proxy)` entry, raw bytes              | 1,258,956         | 854,495                                                                            |

Composites (calls to waves): `inviteWithinSeats` 6 to 3 waves, `offboardEmployee` 8 calls in 2 waves, `reconcileAccount` 2 calls, `onboardEmployee` 8 calls, `bookWithReminder` 8 calls, `payDueBills` 6 calls, `openTicket` 4 calls in 2 waves, `closeAccountingPeriod` 2 calls in 2 waves. The generated report in [example-perf.md](example-perf.md) holds every row.

What changed: the shared session memo and bitset permission claim, the shell bootstrap with a kept entry, `heldPermissions` for record loaders, the `funding_award_usage` lateral aggregate, the proxy trim, and the composites as SQL functions (`book_with_reminder` and `pay_payment_batch` are on `main` as migrations 078 and 079; this branch adds `create_task_with_sla` at 124 and `close_period_if_clear` at 125).

Verification on the merged tree:

- `pnpm verify` (after the second merge of `main`): every task passes except `typecheck:perf`, whose generation timing gates fail locally (cold `gen` about 4 s against a 0.5 s baseline) because `gen` parses the 30 MB of migrations inside the repository. The same check passes in CI on `main` (run 45623587434, head `f96041274a`, conclusion success), so the failure is machine dependent and not caused by this branch. A first local run on `origin/main` gave the same 4.0 s.
- Size baselines: `blocks/tasks` rose from 63,336 to 68,129 bytes gzip because `createTaskWithSla` ships its SQL function. The next-build baselines were regenerated from the current build (the update never raises a number).
- Migrations: `main` already carries `book_with_reminder` and `pay_payment_batch` as 078 and 079, so this branch drops its identical copies and keeps `create_task_with_sla` and `close_period_if_clear`, renamed to 124 and 125 so they sort after `main`'s newest migration (`check:migration-order`).
- The five specs that failed under load pass alone: `setProductStatus` (needed a product URL, see below), the eval run page, the API key page, the work order page, and the deals calendar view (the seed closes the deal 12 days out, which can be next month while the grid opens on the current one, so the spec now opens the seeded month).
- Playwright, full suite on ports 3400 and 3401 after `supabase:reset` and `resolve-urls`: 1604 passed and 73 failed in the `chromium` project (down from 121), and 18 passed and 1 failed in `counters`. Causes of the 73:
  - 66 are `instant-routes` cases of detail routes: the title heading sits behind the page's `Suspense` boundary, so it is not in the prefetched UI under the instant lock. No `page.tsx` under `apps/examples/nextjs/src/app` differs from `origin/main`, so the shells are the ones `main` has. The pages state "the back link is the static shell", and the record streams in; there is no shared detail layout to change, because each page owns its `Suspense` fallback (the 40 or so that pass have a heading in the skeleton). The fix is a static heading in about 60 skeletons, or one decision to drop the heading from the instant check for streamed records. I left it as recorded; it is a design call, not a regression. I did not rerun five of them on `main` (no build there), the identical page files stand in for it.
  - 3 are `budgets` cases that now render and measure: `/customers/[id]` (14 calls against 13, the deferred sections start inside the window), `/crm/deals/[id]` (13 calls in 4 waves against 12 in 3) and `/crm/companies/[id]` (9 calls in 4 waves against 3 waves). None of the loaders are touched by this branch; they need a budget decision or a waterfall fix.
  - 4 are the workflow builder route (budgets, cold-warm, db-time, measure-pages) opened with a stale definition id. `urls.json` kept an id from an earlier run after the reset. `resolve-urls` now forgets the URL of a route it cannot resolve, and the four cases pass alone.
  - 1 in `counters`: `islands.spec.ts` "a second instance serves the remote entry" landed on a login page. The cause was the test, not the branch: it read the second instance from a fixed `localhost:3101`, so a run on `BSB_PORT=3400` reached another checkout's server. It now follows `BSB_PORT` and passes alone and with the other four islands cases. `main` has the same fixed port. `bsb-main-probe` has no install or build, so I did not run it there.
- The 116 missing-`h1` failures reported earlier had three causes. Nine pages put their title in a `div` or `h2` (case, framework, lesson, contact, meeting, metric, rule, course, builder): they now have a level 1 heading. Two routes read other tables than `resolve-urls` assumed (`subject_collections` has no seed, so `/shop/collections/[id]` is skipped as unresolved; `/warehouse/counts/[id]` now reads `count_plans`). `/shop/products/[id]` had no seeded URL at all.
- The Schema check failed on a stale `supabase/snapshot.json` after the migration renames; regenerated with `supabase:reset` and `gen --save-snapshot`. `verify / coverage` failed on the unit duration check: `actor-write-guard.test.ts` ("guards every authenticated write" 11.0 s, "gives authenticated no permissive for-all policy" 10.3 s) and `scope.test.ts` ("leaves no organization identifier but parameter names" 10.2 s) passed the half-timeout line of 10 s. They are not slower because of this branch: locally they take about 1 s each (3 s with coverage), the branch adds two small SQL functions to a render of hundreds of modules, and every other file in the same run ran 1.3 to 1.7 times over its budget (`over-app-tables` 184 s against 111 s, 3092 s of total test time on a loaded runner). `actor-write-guard` rendered all schema modules twice, so it now renders them once in `beforeAll`; `scope.test.ts` renders its modules in `beforeAll` too. The assertions did not change.
- The machine carried a load average of 8 to 38 from other agents, so timing numbers are indicative.

Manual steps for the maintainer:

1. Apply the migrations to the hosted project (`20270120010124` and `20270120010125`, after `main`'s newest `...123`).
2. Set `BSB_KEPT_STORE=vercel` in the Development, Preview and Production environments, then run the kept-entry probe against a preview. A kept read after a deploy is untested on Vercel.
3. Apply the plans anon-read migration (`20270120010074` and `20270120010080`) before the plan catalog read as `anon` goes out.
4. Adopters run `better-supabase upgrade` to pick up the composite functions and the bitset claim; a part's TypeScript hooks no longer fire inside a composite, the composite's own hook does.

## Measured after the changes (calm enough: load 8 to 10)

Admin, `db-time` spec (`BSB_DB_ADMIN_URL` set to this checkout's database; the default points at the main checkout's port), seed tier, warm render. Before is the first harness table in this file's sibling, [one-round-trip-before.md](one-round-trip-before.md).

| Route                   | Statements | Exec ms before to after | Plan ms after | Buffers before to after        |
| ----------------------- | ---------- | ----------------------- | ------------- | ------------------------------ |
| `/funding`              | 14 to 11   | 1790.73 to 99.24        | 2.31          | 52707 to 4267                  |
| `/care/[clientId]`      | 25 to 22   | 1203.12 to 70.92        | 2.90          | 30489 to 3505                  |
| `/medications`          | 12 to 9    | 480.32 to 30.04         | 2.39          | 10273 to 1223                  |
| `/care`                 | 20 to 18   | 359.92 to 180.56        | 9.56          | 16465 to 5977                  |
| `/banking/transactions` | 12 to 9    | 210.92 to 89.35         | 2.83          | 15041 to 12063                 |
| `/deadlines`            | 11 to 8    | 81.16 to 11.88          | 3.79          | 3589 to 472                    |
| `/crm/deals`            | n/a        | n/a                     | 2.80          | 2672 (13 statements, 35.76 ms) |

Buffers and statements are exact; milliseconds vary with the load. `/care/[clientId]` is 18 calls in 2 waves (before 21 in 2). The planning time of `better_supabase.funding_award_usage(uuid)` at the seed tier is 0.01 ms for the call (a nested function body is planned inside the call), 0.3 to 1.0 ms to execute and 6 to 518 buffers; the earlier 162 and 69 ms planning figures came from a larger award, not reproducible at the seed tier.

Server bundles, raw bytes from `tests/next-build/server-baseline.json`, `main` then this branch: `(proxy)` 1,302,300 to 854,641 (minus 34.4 percent); all page entries 1,127,110,664 to 1,127,281,212 (plus 170,548 over 294 entries, about 0.6 KB each); all API route entries 297,179,773 to 297,214,770 (plus 34,997).

To measure again in a worktree: `pnpm supabase:reset`, then `BSB_PORT=3400 BSB_REMOTE_CACHE_DIR=/tmp/bsb-remote-cache pnpm exec playwright test resolve-urls --project=chromium`, then the `db-time` and `measure-pages` specs with `BSB_DB_ADMIN_URL` set to the worktree's own database (its default is the main checkout's port, so a run without it reads and changes the wrong database). Take the numbers with a load average under 8; statements and buffers do not depend on it, milliseconds do.

## Token and cookie size

The access token hook writes the `permissions` claim as a bitset (ADR 1231).

| Role   | Token bytes     | Cookie bytes    | Chunks    | Request header bytes |
| ------ | --------------- | --------------- | --------- | -------------------- |
| admin  | 1494 (was 4035) | 2179 (was 5567) | 1 (was 2) | 2246 (was 5658)      |
| member | 1324 (was 1187) | 1953 (was 1770) | 1         | 2020 (was 1837)      |

A member's token grew by 137 bytes because the claim now carries the 160 byte bitset instead of `permissions_truncated`. The member's permissions are in the token, so a gated page no longer reads `my_permissions()`.

## Verifications and proxy

| Scenario                  | Verifications before | after | Proxy ms before | after |
| ------------------------- | -------------------- | ----- | --------------- | ----- |
| refresh /customers admin  | 2                    | 1     | 32.4            | 31.8  |
| refresh /customers member | 3                    | 1     | 33.8            | 40.4  |

Warm renders verify 0 times, as before. The refresh itself (28 ms to 39 ms) is the Auth server call and is the floor.

## Database time

The before table showed planning at 9% of database time, which seemed to refute the plan's planning hypothesis. It did not: `pg_stat_statements` tracks top-level statements, and the planning and executor start-up of a SQL function body are charged to the call. Measured on `funding_award_usage` for one award as admin:

| Step                                      | Planning ms | Execution ms | Buffers        |
| ----------------------------------------- | ----------- | ------------ | -------------- |
| Before (scalar subquery used three times) | 162         | 316          | 19634          |
| After (lateral aggregate)                 | 69          | 61           | 13184          |
| Function call, first call in a session    | n/a         | 478 to 145   | 23361 to 16627 |

Cause: the planner flattened the derived table `s` and copied the scalar `used` subquery into each of its three uses, so the deliveries policy ran three times per period. The fix is in the generator (`funding-functions.ts`) with migration `20270120010068`.

## Why the rest of the slow routes stay slow

Each `bsb_` read policy and the restrictive `bsb_tenant_scope_select` both carry a `case subject_type` over every registered record type (55 in the example), about 16 KB of expression each. A table with that policy costs 600 to 700 buffers and 2 to 4 ms to read three rows, and a policy that names another such table (deliveries naming awards) nests it. /funding, /care/[clientId], /medications and /care are execution bound for that reason.

Not done, with reasons:

- Shrinking the `case` (a call to one function above N types, or per block `on` lists) changes every generated policy, the goldens and the security review of ADR 0099 and 0104. It needs its own ADR and a measured comparison of inline against function call.
- The restrictive scope repeats the permissive branches by design (ADR 0104). Removing the repeat needs a different way to widen for guests and platform staff.
- `deliveries` policy writes `x.tenant_id = x.tenant_id`, a tautology, where `funding_deliveries.tenant_id` is meant. It is harmless because the tenant is checked by `tenant_ids_with`, but it is worth fixing in the generator.

## Todos not done in this pass

| Todo                                                       | Status  | Reason                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| read-set-gaps (record entry, dependent entry, keyset page) | partial | The record entry exists (`s.record`, `record_summary`). The record server page read is done: `heldPermissions` removes the six `my_permissions` calls per `/customers/[id]` render (ADR 1234). A dependent entry and a keyset page entry are skipped: the spike below shows no page that one would speed up. |
| page-spike                                                 | done    | See "Page spike" below.                                                                                                                                                                                                                                                                                      |
| page-rollout                                               | skipped | The spike finds no route where one call is faster than the parallel calls.                                                                                                                                                                                                                                   |
| action-composites                                          | partial | One SQL function per composite (ADR 1235); see "Action composites" for the ones done and the reason for each one kept.                                                                                                                                                                                       |
| cache-track remainder, cache-tiers, cache-invalidation     | skipped | Not started in this pass. Bare `refresh()` count measured: 139 calls in 98 files, against 372 tag-based refreshes in 126 files.                                                                                                                                                                              |
| size-bundles, report-leftovers                             | partial | The bundle size baselines were not run in this pass. `permission-bitset.ts` adds a small md5 to the claims entry, so run `tests/bundle` before merging.                                                                                                                                                      |

## Shell bootstrap (ADR 1233)

`public.shell_bootstrap` returns organizations, profile, approvals and compact permissions in one call, read through one private entry (`getShell`). Production build, `next start`, warm render, calls per hard load:

| Route               | Calls before | Calls after | Waves before to after (admin) |
| ------------------- | ------------ | ----------- | ----------------------------- |
| `/finance/invoices` | 4            | 2           | 1 to 1                        |
| `/settings/roles`   | 4            | 2           | 1 to 1                        |
| `/customers`        | 7            | 5           | 1 to 1                        |
| `/`                 | 5            | 3           | 2 to 1                        |
| `/customers/[id]`   | 13           | 11          | 3 to 3                        |
| `/crm/deals`        | 16           | 14          | 1 to 1                        |

A first attempt where each reader called `bootShell()` left calls unchanged: React `cache()` does not span `'use cache: private'` scopes.

## Record flags without `my_permissions` (ADR 1234)

`bsb.record(type).load()` asked `my_permissions({ tenant, keys })` in every private
scope, although the token claim and the shell entry hold the keys. Six calls per
render on `/customers/[id]` (fetch log of the harness run, admin and member).
`NextOptions.heldPermissions` now answers first. After: 0 `my_permissions` calls
in the whole run; waves on `/customers/[id]` 3 to 2. The header count rises from
11 to 15 because the deferred sections now start before the header is written,
not because a call was added.

## Page spike

Database time of the parallel calls, from `db-time` (admin, pg statements):

| Route                   | Statements | Exec ms (sum) | Plan ms | Buffers | Waves                       |
| ----------------------- | ---------- | ------------- | ------- | ------- | --------------------------- |
| `/crm/deals`            | 14         | 37.5          | 3.0     | 4363    | 1                           |
| `/customers/[id]`       | 17         | 21.7          | 4.0     | 6113    | 2 after item 1 and ADR 1234 |
| `/inbox/[conversation]` | 19         | 83.8          | 4.6     | 7330    | 2                           |

One call runs its entries in one backend, one after the other, so its database
time is at least the sum of the executions. The parallel calls cost the longest
wave. `/crm/deals` has one wave, so a read set would add the other 13 calls to
the slowest one. `/inbox/[conversation]` has two dependent reads and 84 ms of
execution, mostly one statement. `/customers/[id]` is the only route near
break-even on database time, and its remaining calls are deferred sections that
stream after the shell, which a read set would put back in front of it.
Exceptions (parallel calls kept): all three, for the reasons above.

## Action baselines

Admin, `next start`, calls and waves per action (`actions.spec.ts`):

| Action                | Calls | Waves | ms    |
| --------------------- | ----- | ----- | ----- |
| inviteWithinSeats     | 10    | 6     | 141.7 |
| discussCase           | 5     | 2     | 59.3  |
| openTicket            | 6     | 3     | 57.2  |
| payDueBills           | 7     | 4     | 56.0  |
| reconcileAccount      | 11    | 3     | 51.4  |
| onboardEmployee       | 10    | 3     | 45.4  |
| offboardEmployee      | 12    | 4     | 38.4  |
| closeAccountingPeriod | 4     | 3     | 33.5  |
| bookWithReminder      | 9     | 2     | 21.9  |

## Action composites (ADR 1235)

Admin, `next start`, `actions.spec.ts`. After the composite is one call, the rest of an action's calls are the page re-render that `refresh()` starts (members, roles, teams, `entitlement_value`, shell).

| Action                | Calls before | Calls after | Waves before to after | Commit     |
| --------------------- | ------------ | ----------- | --------------------- | ---------- |
| inviteWithinSeats     | 10           | 7           | 6 to 3                | aca51816e  |
| offboardEmployee      | 12           | 8           | 4 to 2                | 181affa563 |
| reconcileAccount      | 11           | 2           | 3 to 2                | 7b60090543 |
| onboardEmployee       | 10           | 8           | 3 to 2                | fbdbda00cd |
| bookWithReminder      | 9            | 8           | 2 to 2                | eab25f2535 |
| payDueBills           | 7            | 6           | 4 to 4                | 4a9a637725 |
| openTicket            | 6            | 4           | 3 to 2                | a93d8063fc |
| closeAccountingPeriod | 4            | 2           | 3 to 2                | 61760799cd |
| discussCase (kept)    | 5            | 4           | 2 to 2                | none       |

`discussCase` stays as is. The app passes no tags, so `collaboration.discuss` is one `create_comment` call already; the measured drop from 5 to 4 calls comes from the shell work, not from the composite. A SQL function would only pay off for a caller that attaches tags, where it replaces one `attach` call per tag.

## Cache tiers and invalidation (ADRs 1240, 1241, 1244, 1245)

Measured on the production build with `next start`, the local stack,
`BSB_REMOTE_CACHE_STORE=postgres` and, after, `BSB_KEPT_STORE=postgres`.
`tests/cache.spec.ts` loads each route as the admin twice, as a member of the
same organization once, and as the admin on a fresh `next start` process. The
cells are database calls per hard load, before then after.

| Route                   | Hard load 1 | Hard load 2 | Second user | After a restart |
| ----------------------- | ----------- | ----------- | ----------- | --------------- |
| `/`                     | 3 to 2      | 3 to 2      | 3 to 2      | 3 to 2          |
| `/customers`            | 5 to 4      | 5 to 4      | 5 to 4      | 5 to 4          |
| `/crm/deals`            | 14 to 13    | 14 to 13    | 14 to 13    | 14 to 13        |
| `/finance/invoices`     | 2 to 1      | 2 to 1      | 2 to 1      | 2 to 1          |
| `/settings/roles`       | 2 to 1      | 2 to 1      | 2 to 1      | 2 to 1          |
| `/announcements`        | 2 to 1      | 2 to 1      | 2 to 1      | 2 to 1          |
| `/islands?scope=remote` | 1 to 1      | 0 to 0      | 1 to 1      | 1 to 1          |

The call each page lost is the shell's `shell_bootstrap`: the kept shell entry
(item 2) is read from the Postgres kept store by the second user and by the
process that started after the restart, where a `"use cache: private"` entry
could not be. The entry is 8.3 kB. The home page went from one wave to two on the three
loads that read it from the store; I did not find out why. Private entries still miss five to eight times per load on every route:
they live in the browser, so none survives a hard load, and nothing else moves
them. The islands remote entry is a hit on the second hard load only; it did
not survive the restart in either run, which is the Next.js handler's key (it
holds the build), not the kept store.

### Items not done, and why

- Tenant sharing for the permissions block (item 3) and the tenant-shared
  reads that depend on it (item 4): `better-supabase config functions
  --shareable` fails on the example with "The config sets no authorization
  provider, so no function can be shared per tenant", so no function passes. A
  provider needs its own `tables`, `scopes` and `functions`; the permissions
  block has none, so `share: "tenant"` has no table to name. Item 4 is
  skipped on that measurement. Item 3 needs a design (a `share` option on the
  permissions block that feeds `tables`, `permissionsShareKey` and doctor
  BS428/BS430) and is not started.
- Item 5 landed (ADR 1244): `getPlans` reads as `anon` through `bsb.public()`.
  The plan tables gained an anon select grant in a new migration.

### Bare `refresh()` calls

About 140 bare `refresh()` calls, counting comments that name it. `src/lib/refresh-caller.ts` holds
three of them on purpose. The rest, by reason:

- Most of the rest sit in `"use server"` functions named `retry*` or `refresh*`, with
  no write in them: the Retry button of a load error or a live list. A retry
  re-renders; nothing changed in the database, so no tag applies.
- Mutations in domains whose pages read without a cache (`agents`, `evals`,
  `ai-tasks`, `ai-providers`, `ai-usage`, `guardrails`, `knowledge`,
  `notifications`, `prompts`, `assistant`, `records`, `workflows`): their reads
  go through `bsbCore.context()`, which holds no entry, so `refresh()` renders
  the new rows.
- `composites-actions.ts` belongs to the composites work.
- Fixed here: the organization, invitation, profile and avatar actions, the
  plan review step and the integration disconnect. Their pages read from
  `"use cache: private"` entries, which a production server keeps after
  `refresh()`. They now call `refreshCaller(auth)` (the session) or, for the
  disconnect, `refreshCaller(auth, [CONNECTORS_TAG])`.

`tests/features/refresh-tags.test.ts` is the guard for the tagged calls: every
tag passed to `refreshCaller` must be carried by a read, and an action that
writes a table with a domain tag of its own must pass that tag. It starts at
zero findings and a call that drops `CUSTOMERS_TAG` fails it.

## Follow-up pass: measurements and skips

### Auth memo (Track 1)

The shared session memo, its counters (ADR 1247), the sign-in seeding, the JWKS warm and the single cookie parse are in place and verified by their tests. Parsing the `ssrSession` cookie and verifying its token costs about 34 µs unmemoized and 0.8 µs memoized on a laptop. The 34 µs figure uses a locally cached JWKS; a cold JWKS fetch is a network call and is what the warm step removes.

### Unexplained calls (Track 0)

`DbStats.trace` (a stats field, with a changeset) records each call with its start, end, wave and phase (`action` or `render`). `tests/explain-calls.spec.ts` writes one trace per route to `perf-results/example-perf/explain-<user>-<route>.json` (set `BSB_EXPLAIN_ROUTES` to choose routes). Use them to attribute the extra calls on `/customers/[id]`, `/crm/deals` and the bench-scope verifications to a phase and a wave.

The db-time spec's "failing detail routes" were stale ids: `resolve-urls.spec` writes `urls.json`, and a database reseed makes every id in it dangle, so the detail page renders its error boundary and has no `h1`. Run `resolve-urls` before `db-time`; the nightly workflow does.

### Database time (nightly and doctor)

`.github/workflows/example-db-time.yml` runs `resolve-urls` and `db-time` every night and on demand. `db-time.spec.ts` compares each route's buffers with `tests/db-time.baseline.<tier>.json` (growth of 25 percent plus 64 buffers). Without a baseline file the spec only records. Write the baseline on a quiet machine with `BSB_DB_TIME_UPDATE=1`. The local attempt in this pass was skipped: the machine had a load average above 20 and the 248 routes did not finish before the server stopped answering, so no number would have been trustworthy.

Doctor rule BS732 (ADR 1246) warns about statements from the API roles and functions that average more than 100 ms over at least five calls, and says when `pg_stat_statements` is not installed.

### Proxy and bundles (Track 5)

The proxy loads `./flags` lazily and takes the visitor cookie name from `visitor-cookie.ts`. The `(proxy)` entry went from 1,258,956 to 854,495 raw bytes (32 percent). A content test in `tests/next-build` keeps the flag keys out of the proxy chunks. Of what remains, a 628 KB chunk is the permission catalog, which the proxy needs to read the permission bitset, and a 158 KB chunk holds the navigation items it needs for `requiredPermission`. Decisions after measuring: `next-intl` stays in the proxy (the locale redirect is the proxy's job and its code is a small part of the 158 KB chunk), and the refresh policy stays as it is (only the proxy refreshes, invariant 7), so neither changes.

The next-build baselines were retaken against a build without `EXPOSE_TESTING_API`: server chunks grew 43 KB on pages and about 160 KB on API routes since the last retake, which comes from branch work on shared chunks (cache tiers, composites, the stats trace) and is not attributed to one change. The library baselines in `tests/bundle` were retaken too (`./server` 223,875 to 235,715 B gzip, `./claims` 18,421 to 20,361 B gzip). Building the bundle test found a module-level `TextEncoder` in `core/stats.ts` that broke imports on runtimes without one; it is created on first use now.

`banking.ts` was over the 1000 line limit, so the row mappers moved into `mappers.ts` as a pure move with no export changes.

### JWT size

The header size check already exists, so there is nothing to add.

### Not run: routes without an `h1` and the db-time baseline

The `h1` check (a sign-in, then every openable route with a 6 second wait for a level-1 heading) and the full db-time baseline did not finish. With a load average of 11 to 24 from other jobs on the machine, the production server on the example's own port stopped answering and the resolve-urls pass slowed from 4 minutes to 11 minutes for 10 routes. The 23 routes in the plan are the detail routes whose seeded id had gone stale (see above), so a fresh `resolve-urls` should remove most of them; the first fresh run found `/metrics/[key]` still without an `h1`. Run `resolve-urls` then `db-time` on a quiet machine (the nightly workflow does), set `BSB_DB_TIME_UPDATE=1` once to write `tests/db-time.baseline.seed.json`, and fix any route the run lists.

### Skipped, with the reason

| Item                                        | Reason                                                                                                                                 |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Dependent entry, keyset page entry          | The page spike finds no route where one call beats the parallel calls. A keyset cursor entry fails at compile time ("Invalid cursor"). |
| Page rollout, tenant-shared `bsb.kept`      | No gain in the spike, so no kit rollout and no shared reference data.                                                                  |
| Lazy Supabase client parts                  | The client is one 235 KB chunk; splitting it needs an upstream change.                                                                 |
| Per-area block sets, finance pages split    | Not measured to pay off before the baselines can be regenerated on a quiet machine.                                                    |
| Lazy kanban and drag and drop (about 50 KB) | Left for the bundle pass; the pages that use them are not the chatty ones.                                                             |
| Instant lock on search params               | `@next/playwright` cannot lock a navigation that only changes search params.                                                           |
