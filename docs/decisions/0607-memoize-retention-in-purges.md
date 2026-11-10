# 0607: Ask the policy tables once per tenant in a purge

- Status: accepted
- Date: 2026-11-10

## Context

Every purge's where clause calls `retention_for(kind, tenant)` and `is_held(kind, tenant)` per
candidate row (about 20 functions, one shared template). Both are stable but Postgres never
caches a stable call across rows, and `retention_for` is plpgsql with a plan lookup. Measured on
100,000 expired outbox events in two tenants with no policy: the delete alone takes 46 ms, the
predicate 2,193 ms, `purge_outbox` 2,343 ms.

## Decision

`retention_for_memo` and `is_held_memo` (security invoker, volatile) answer through
`better_supabase.memo_get` and `memo_set`, a transaction-local setting keyed on the kind, the
tenant and `statement_timestamp()`. A purge asks the policy tables once per tenant and statement;
a later statement in the same transaction asks again, so a policy or a hold placed between two
purges takes effect. The shared `retention` and `held` builders in the SQL context call them, so
every purge gets it. `retention_for` and `is_held` stay exact for other callers.

## Measured

`purge_outbox` on the same 100,000 events: 540 ms (4.3 times faster). On the 60,000-row pgTAP
fixture (`scale_retention_purge`): 313 ms against 990 ms for the per-row predicate; the same file
checks that a hold and a shorter policy are honoured by a later statement of the transaction.
The rest of the 540 ms is the memo call per row, not the policy tables.

## Not done

- No index dropped: `pg_stat_user_indexes` has no usage after a reset of the local stack, so the
  `outbox_events` indexes stay. The `webhook_deliveries` `created_at` index the plan asked for
  already exists as `webhook_deliveries_finished_idx` (partial on finished statuses) and
  `webhook_deliveries_tenant_created_idx`.
- `drive-lifecycle` still calls `retention_for` directly, in a trigger's own predicate.

## Consequences

`better-supabase upgrade` rewrites `data-lifecycle` and every module with a purge; the migration
adds two functions and replaces the purge functions.
