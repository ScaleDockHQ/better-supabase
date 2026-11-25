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

| Todo                                                   | Status  | Reason                                                                                                                                                                               |
| ------------------------------------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| shell-bootstrap, read-set-gaps                         | skipped | Needs the permission snapshot and read sets reworked on a page by page basis; the bitset already answers the proxy gate and the member snapshot without `my_permissions()`.          |
| page-spike, page-rollout, action-composites            | skipped | The measured waves per page are 1 (median) for admin and 2 for member; the database time of the slow routes is execution bound in the policy size above, not in the number of calls. |
| db-track, cache-track, cache-tiers, cache-invalidation | skipped | Depend on a page rollout that was not done.                                                                                                                                          |
| size-bundles, report-leftovers                         | partial | The bundle size baselines were not run in this pass. `permission-bitset.ts` adds a small md5 to the claims entry, so run `tests/bundle` before merging.                              |
