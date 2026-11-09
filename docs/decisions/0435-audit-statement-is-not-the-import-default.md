# 0435: Keep the row trigger as the audit default for import targets

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

The scale report proposed `audit.statement` (one statement trigger over the
transition tables) as the default for import targets, expecting the per-row audit
trigger to dominate a large batch. In `summary` mode (ADR 0422) the row trigger
no longer starts at all, so the question is only about `rows` mode.

## Measured

`supabase/tests/scale/scale_audit_modes.test.sql`: 3,000 inserts into one block
table, two runs on the local stack:

| Mode                                    | Run 1    | Run 2    |
| --------------------------------------- | -------- | -------- |
| No audit                                | 679 ms   | 689 ms   |
| Deferred row trigger (default)          | 1,431 ms | 1,391 ms |
| Statement trigger (`statement => true`) | 1,663 ms | 1,706 ms |

The row trigger costs about 0.24 ms per row over no audit. The statement trigger
costs about 0.33 ms per row: it writes the same entries with the same per-row work
inside one `insert ... select`, and loses the deferral that lets a transaction
coalesce its work.

## Decision

The default stays the deferred row trigger, and `audit.statement` stays opt-in. No
code changes. A batch that needs less audit cost uses `imports.audit: summary`
(ADR 0422), which writes no row entries during the run and one per entity at its
end, or an app table exempt from audit.

## Consequences

No module is rewritten and no data migration is needed; nothing breaks. If a later
Postgres or a set-based audit writer changes the numbers, rerun the scale test and
revisit.
