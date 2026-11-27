# CentraKit performance review: what changed and what is measured

Checked on `perf/centrakit-checks-after-088`, which starts from main after 0.88.0
(PR 1172) and the merges of PR 1174 and PR 1175. The Vercel tag probe stays a
maintainer run. The proxy stays above 400 KB because Next's runtime is most of
the bundle.

| Item               | What holds                                                                                                                                                                                                                                                                                                                                | Evidence                                                                                                                                                                                                                                                         |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Request stats   | `connect()` both ways, `bsb.phase`, `decodes` and `keptHits` report on the request recorder. `read_batch` is one call. A gated `bsb.tenant({ gate: true })` runs its check beside the first call, so the read itself is one executor call.                                                                                                | `tests/validation-centrakit/src/stats-parity.test.ts`: the pool path (both `connect()` forms and one `read_batch`) matched `pg_stat_statements` at 5 calls, and the supabase-js path matched at 1. A browser `verifySession` call is not on the server recorder. |
| 2. BS428           | The cast pattern matches `::text`, `::character varying` and array casts as Postgres deparses them. Doctor also reads the schema of a schema-qualified `authorization.tables` name when `schemas` does not list it.                                                                                                                       | Unit fixtures. On the CentraKit copy, `--only BS428` is 0 after that read. Before it, the same run reported 2, both `private` tables the catalog had omitted.                                                                                                    |
| 3. Kept reads      | `cached({ keep })` keeps a stable `$rpc` and a `$many` batch when `keep.tables` names the tables, one entry for the call. A volatile function, a call with no tables, a failed call, a support session and an invalid token still reach the database. `bootstrap({ kept })` still skips a signed-out caller, including `require: "user"`. | `tests/next/cached-keep.test.ts` (10 tests). `tests/cache.spec.ts` on the example, memory store: see the table below. The target of 0 or 1 calls is not met except `/islands?scope=remote` on the second hard load.                                              |
| 4. Tags            | `bsb.expireTags` writes the kept store. `bsb.action` and `bsb.blockAction` expire `invalidates` and `tags()` through that path.                                                                                                                                                                                                           | Unit tests. The example's `refreshCaller` calls `expireTags` when the caller passes tags.                                                                                                                                                                        |
| 5. Actions         | `bsb.action` settles inside the `action` phase, and `blockAction` goes through that helper.                                                                                                                                                                                                                                               | The 13 `refreshCaller` sites stay. They do not import `refresh` from `next/cache` themselves, so BS649 does not fire on them. A bare `refreshCaller(auth)` expires the session. The rest pass tags.                                                              |
| 6. Proxy           | The example proxy imports only `better-supabase/next/proxy`.                                                                                                                                                                                                                                                                              | `tests/next-build/server-baseline.json` records 714,965 bytes raw. The ceiling stays 720 KB.                                                                                                                                                                     |
| 7. Release         | 0.88.0 is published. PR 1174 and PR 1175 are merged and wait in `.changeset/`.                                                                                                                                                                                                                                                            | The tag probe is not run.                                                                                                                                                                                                                                        |
| 8. Doctor          | `--out` is checked up front. BS609 names a read set, `read_batch` (what `bsb.record(type).get` uses) and `bsb.bootstrap`.                                                                                                                                                                                                                 | `doctor --stats --as test@example.com` on the CentraKit copy took 142.3 s (read the project 1.5 s, run the rules 123.6 s).                                                                                                                                       |
| 9. Authz subscribe | The channel joins when the browser is idle, one channel per client, topic and event. `liveVersion` skips `caller_authz_version()` on the first join.                                                                                                                                                                                      | The example passes the layout's live read, not the token claim. One hard reload of `/customers/[id]`: see below.                                                                                                                                                 |

## Before and after

| Measure                                                    | Before                                                                                   | After                                                                                                                                                                                                                                                           |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stats parity                                               | Not measured                                                                             | Pool path 5 calls = 5 statements. supabase-js path 1 = 1.                                                                                                                                                                                                       |
| cache.spec calls (hard 1 / hard 2 / second user / restart) | Not measured                                                                             | `/` 7/7/7/7, `/customers` 5/3/5/5, `/crm/deals` 5/5/5/5, `/finance/invoices` 4/4/4/4, `/settings/roles` 2/2/2/2, `/announcements` 2/2/2/2, `/islands?scope=remote` 2/1/2/2                                                                                      |
| Detail budgets, calls and waves                            | PR 1175: customers 8/2, deals 8/3, invoices 10/2, payables 10/2, risks 6/2, dispatch 9/3 | Three runs: customers 10 (waves 2, then 3, then 3), invoices 12/3, payables 11/3, risks 7/2, dispatch 10/3. Deals was not opened: this seed has no deals.                                                                                                       |
| Proxy bytes                                                | 716,096 in the previous note. The committed baseline is 714,965                          | 714,965 raw. 400 KB is not met.                                                                                                                                                                                                                                 |
| Realtime statements on one hard reload                     | Not measured (the note expected 4)                                                       | With `liveVersion`: 0 browser calls to `caller_authz_version`, 1 PostgREST version statement (the server read), and 5 calls of each of the three realtime statement shapes. Without it: 1 browser call and 2 version statements. The realtime shapes stay at 5. |
| BS428 findings                                             | Not run                                                                                  | 0 after doctor reads the declared schemas. The run before that fix reported 2, both tables in `private`.                                                                                                                                                        |
| Doctor `--stats` time                                      | About 3.5 minutes                                                                        | 142.3 s wall for `--stats --as test@example.com`. Rules took 123.6 s.                                                                                                                                                                                           |
| Version reads                                              | The example did not pass `liveVersion`                                                   | One `caller_authz_version()` per signed-in page, from the layout. The client does not repeat it when that number is passed.                                                                                                                                     |
| Memberships in 1,024 bytes                                 | Not measured                                                                             | 13 memberships, one role each: the compact claim is 487 bytes and fits. The older claim is 1,171 bytes, keeps 11 and sets truncated.                                                                                                                            |
| Snapshot bytes, 1 / 3 / 10 custom roles                    | Not measured                                                                             | Named form 2,704 / 2,916 / 4,975 bytes. Inline form 3,145 / 3,943 / 9,095. The named form is smaller at each count.                                                                                                                                             |

## Kept reads on the example

`keep.tables` is `keyof Models`, and the example schema does not include the
block tables behind deals, invoices, roles or announcements. Those readers stay
on `bsb.cached()` with no `keep`. Tagging another table would expire the wrong
rows. The home summary does keep `customers` and `notes`, and the islands
bootstrap uses `kept: true`.

The second hard load is still above one call on six of the seven routes. The
restart column matches the first hard load because `BSB_KEPT_STORE` defaults to
memory, and a new `next start` does not see the previous process. Islands is
the exception on the second hard load: 1 call, which is the live version read.

## Detail budgets

The signed-in layout reads `caller_authz_version()` so `SessionProvider` can
skip the catch-up RPC (EX-1615). That is one counted call on every signed-in
page. The five detail ceilings the measurement put one call over now include
it: `/customers/[id]` 10, `/finance/invoices/[id]` 12, `/finance/payables/[id]`
11, `/risks/[id]` 7, `/field/dispatch/[id]` 10. Waves stayed inside the
existing ceilings. A fresh confirmation run of those five tests passed.
`/crm/deals/[id]` has no row in `better_supabase.deals` on this stack, so it
was not remeasured.

## Authz statements

Measured on one hard reload of `/customers/[id]` after the first join had
settled, against `pg_stat_statements` and the browser's requests.

With `liveVersion` the browser made no request to `caller_authz_version`.
Postgres recorded one PostgREST call of `api.caller_authz_version()` (the
server read) and five calls each of `select` on `realtime.messages`, the
realtime `set_config` statement, and `insert` into `realtime.messages`. One
websocket opened.

Without the prop, the same reload added the browser catch-up: two PostgREST
version statements, and the same five calls of each realtime shape. The channel
still joins. The version read moved from the client to the server. It was not
removed.

## The 13 refresh callers

`refreshCaller` in `apps/examples/nextjs/src/lib/refresh-caller.ts` calls
`bsb.expireTags` when tags are passed, and `evictSession` for a user with no
tags. The call sites stay: webhooks (3), customers (2), and one each in user,
teams, support, service principals, projects, jobs, imports and domains. The
bare call is the session-wide one in the user actions. BS649 looks for a
direct `refresh` import, which these files do not have.

## Known limits

- `bootstrap({ kept })` can serve an ended session for up to `life.revalidate`
  seconds (default 30) unless `bsb.evictSession` runs. A signed-out caller is
  not stored.
- A stable function and a `db.$many()` batch are kept when `keep.tables` is
  set. A volatile function, a call with no tables, function source and raw SQL
  always reach the database. A failed call is not stored.
- The example cannot name a block table that its generated `Models` type does
  not include, so those reads are not kept.
- The proxy's own token decodes are not counted in `decodes`.
- A client `verifySession` call does not appear on the server recorder. The
  proxy's check does, when it is turned on.

## Maintainer steps

1. Apply the migrations from the release.
2. Set `BSB_KEPT_STORE=vercel` in the three Vercel environments.
3. Run the probe against a preview and fill the pending rows in
   `(integrations)/vercel/cache.mdx` and the 0.84 to 0.85 guide:

   ```sh
   BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts https://<preview>.vercel.app --second
   ```

## CentraKit stack

The dry run copies CentraKit and points `better-supabase` at this checkout
(`BSB_CHECKOUT`). It does not write the original. The copy's stack is the
database behind the numbers below. `test@example.com` is
`11111111-1111-4111-8111-111111111111`.

The file-based doctor inside the dry run did not load `better-supabase.config.ts`
(the config imports TypeScript without a suffix, and this CLI does not load
jiti). Its JSON counts of 0 are that failure, not a clean report. A later run
with a resolver that adds the suffix did load the config.

| Check                                   | Result                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BS428                                   | 0 findings after doctor reads schemas named by `authorization.tables`. The earlier run, which only read `schemas` plus `better_supabase`, reported 2: `private.organization_dashboard_counts` and `private.planning_absence_overrides`. Both tables exist. Neither has a permissive select policy for `authenticated`. |
| Cast check on tenant tables             | The dry run compared `pg_policies` with `::text` removed for the 28 `share: "tenant"` tables. 28 passed and 0 failed.                                                                                                                                                                                                  |
| `doctor --stats --as test@example.com`  | 142.3 s wall. Read the project 1.5 s, run the rules 123.6 s. Exit 0. BS209, BS405, BS409, BS429 and BS430 were 0. The report had 271 errors, 73 warnings and 1,910 infos, almost all outside this check.                                                                                                               |
| `rls.tableReads`                        | 230 `row` tables and 28 `tenant` tables. `rowWithoutReason` is 0. The `unknown` rule accounts for 17 of the row tables, including the two `private` tables.                                                                                                                                                            |
| `codemod bsb-access-tags --check`       | Would move 0 of 7 tables that still have a plain tenant policy. The 7 stay because another policy covers the same command: `invoices`, `orders`, `purchase_orders`, `quotes`, `employee_journeys`, `task_recurrence_rules` and `tasks`. `couldShareByCodemod` was 0 before the codemod as well.                        |
| `public.*_payload`                      | `inspect` listed 27 functions. The earlier note said 26. None are shared, and each row gives a reason.                                                                                                                                                                                                                 |
| `rls measure --as` a custom-role member | `owner@example.com` holds `seed-finance-settings` in tenant `01010101-0101-4101-8101-010101010101`. The command stopped with `permission denied for table organization_dashboard_counts` before it printed version reads. That table is one of the two `private` tables with no authenticated select policy.           |
| Memberships                             | This seed gives `test@example.com` 11 organizations, and none have `disabled_at` set. The synthetic compact claim for 13 memberships is 487 bytes and fits in 1,024. The authorization provider's current-token helper accepts `memberships` as an array or an object.                                                 |
| `disabled_at`                           | `Principal.suspendedIn` is on the authorization subject. The CentraKit tasks service still maps `member.disabled_at` to `disabledAt`. The column has not been removed from `organization_users`.                                                                                                                       |
| Read-only actor plans                   | 579 policies, 208 tables, 0 failed plans. Median policy cost was under 0.05 ms above the same statement with the policies removed.                                                                                                                                                                                     |

`codemod bsb-action-keys` on the copy exited 1 and said the linked package was
older than 0.84.0. `better-supabase/sql` in this checkout does export
`listActions`. The import from the copy did not see it as a function, so the
codemod did not run.
