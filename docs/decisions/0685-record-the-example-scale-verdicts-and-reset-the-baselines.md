# 0685: Record the example scale verdicts and reset the baselines

- Status: accepted
- Date: 2026-11-12

## Context

Phase 11 of the example coverage plan runs the Next.js example against the
scale tiers. The seed (`pnpm db:seed:scale --tier l`) writes 1,099,903
customers and notes over 1,001 organizations, 1,001,955 audit events and
1,000,001 notification events; it takes 3 minutes 9 seconds on a freshly reset
native stack. Tier XL adds 10,000,000 audit and notification rows. The route
baselines of `tests/next-build` were never measured for the pages of phases 2
to 9, and the route database budgets in `tests/routes.manifest.ts` were still
the archetype ceilings.

## Decision

Keep the example as it is and fix what the measurements show.

Indexes, measured with `EXPLAIN (ANALYZE)` at tier L:

| Read                                 | Before                                          | After                                                         |
| ------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------- |
| customers, newest sort (EX-015)      | 513 ms, parallel seq scan and top-N sort        | 0.045 ms, index `(organization_id, created_at desc, id desc)` |
| search settings list, keyset page    | parallel seq scan of 1,000,000 rows, top-N sort | 0.035 ms, index `(tenant_id, updated_at desc, subject key)`   |
| customers by status, name sort       | 0.4 ms                                          | unchanged                                                     |
| exact count of active customers      | 21 ms                                           | unchanged, the list keeps its capped count                    |
| customers search under three letters | seq scan                                        | deferred, a trigram index needs three                         |

The other admin lists (hostnames, option sets, flags, streams, the webhook
inbox, numbering, OAuth apps) hold hundreds of rows per tenant and keep the
tenant index (EX-500). The pgmq run list is small in the example (EX-501).

The 24 pgTAP files in `supabase/tests/scale` pass at tier L. Each file inserts
its own rows; the two that compare a shape with its replacement show the cost
of the old one:

| File                                | Replacement    | Old shape        |
| ----------------------------------- | -------------- | ---------------- |
| reactions read policy               | 229 ms         | 5,693 ms per row |
| SLA clocks policy                   | 235 ms         | 3,925 ms per row |
| deal contacts policy                | 266 ms         | 3,812 ms per row |
| knowledge documents policy          | 206 ms         | 6,100 ms per row |
| list_risks deep page                | 1 ms keyset    | 16 ms offset     |
| customers count                     | 1 ms capped    | 226 ms exact     |
| audit page                          | 15 ms          |                  |
| customers newest page, by name page | 8.5 ms, 6.2 ms |                  |

`search_global` takes 0.86 to 1.32 s in `scale_search_global.test.sql` (EX-1504,
deferred to the library). `scale_subject_policies_remaining.test.sql` reused a
deal id of the example seed and takes `d9001`.

The Playwright specs (`cold-warm`, `budgets`, `instant-routes`, `instant` and
`loading-sequences`, 391 cases, one worker, production build) pass 389; the
two that did not are a flaky browser context (passed on rerun) and the
settings tab case, which is `test.fixme` until a link reaches the preferences
page (EX-1503). Over 151 routes:

| Timing | p50    | p95      | Slowest             |
| ------ | ------ | -------- | ------------------- |
| cold   | 919 ms | 1,153 ms | `/funding` 4,087 ms |
| warm   | 99 ms  | 438 ms   | `/funding` 1,717 ms |
| client | 27 ms  | 35 ms    | 53 ms               |

150 routes carry a measured database budget (at most 11 calls in 3 waves). The
manifest now holds the measurement plus two calls and one wave: 41 ceilings were
tightened and 20 loosened to the measured calls (EX-1502; `/calendar` makes 11
calls). Every `/settings` page and `/forbidden` had no `h1`, which failed all
three timing specs; they have one now (EX-1500).

Baselines of `tests/next-build`, from a production build, with the ADR 0639
policy (a number is a ceiling, the commit carries before and after):

| Baseline               | Change                                                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------ |
| first load, new routes | 20 routes of phases 2 to 9 added (225 to 245), then 6 from the merged work (251)                                   |
| first load, grown      | 728 numbers: median +4,926 B raw, +1,542 B gzip, +1,225 B brotli                                                   |
| first load, outlier    | `/qualifications` +84,793 B gzip (EX-1505)                                                                         |
| server chunks, new     | 25 routes added (299 to 324), then 8 from the merged work (332)                                                    |
| server chunks, grown   | 353 numbers: median +2,752 B raw, +2,263 B gzip                                                                    |
| payload                | `en/customers.html` +168 B raw, +121 B gzip, `en/projects.html` +30 B raw, +151 B gzip, `en/login.html` +69 B gzip |

The 1,350 empty `nl` strings of the message files are filled. A build writes
both `.po` files in extraction order; that order is committed now, so a build
leaves them unchanged.

## Alternatives considered

- Loosening every budget to one ceiling. The manifest asks for a measurement
  plus slack, and a single number hides the routes that make 11 calls.
- Adding the missing indexes to the library tables. The two reads belong to
  the example's lists, so the indexes live in `supabase/schemas`.
- Waiting for the list generator before writing scale files (EX-1265). The
  EXPLAIN numbers above need no new file.

## Consequences

The example has a measured number for every route and a verdict for every
finding (`docs/agents/example-findings.md`). Revisit the budgets when a page
batches its reads (the calendar), and the baselines when `/qualifications`
loses its extra import.
