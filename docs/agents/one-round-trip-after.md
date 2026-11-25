# One round trip: after numbers and leftovers

Measured the same way as [the before numbers](one-round-trip-before.md): production build, testing API, local stack. Counts are the budget; milliseconds are indicative.

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

| Action            | Calls before | Calls after | Waves before to after | Commit     |
| ----------------- | ------------ | ----------- | --------------------- | ---------- |
| inviteWithinSeats | 10           | 7           | 6 to 3                | aca51816e  |
| offboardEmployee  | 12           | 8           | 4 to 2                | 181affa563 |
