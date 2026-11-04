---
"better-supabase": minor
---

Audit is cheaper per row. The row and statement triggers and `audit_event` read `import_run()` once
into a variable. The row trigger looks up the tenant's name once per tenant and transaction
(`memo_get`/`memo_set`), and the statement trigger joins the organizations table once per distinct
tenant instead of once per row. `sql upgrade` writes one pgTAP file for all audited tables,
`900_better_supabase_audit_tables.test.sql`, and removes the old per-table files.
`blocks.audit.options.exempt` is typed as `readonly (string | { table, reason })[]`; a bare glob
string still works, and doctor reports it (BS315).

The `webhooks-out` delivery indexes (`due`, `open`) use the mapped status values, so an adopted
table with other labels is indexed correctly. Doctor reports a live partial index that differs from
the module's definition (BS363); `create index if not exists` leaves such an index as it was, so
drop it and run `sql upgrade`. The `gen.api` wrappers copy `stable` and `immutable` from the
function they wrap instead of being volatile, so Postgres can inline and cache them; run
`sql upgrade` to rewrite existing wrappers. Doctor reports a volatile wrapper around a stable
function (BS364).

`approvals` adds `approval_eligible_ids(tenant)`, the pending requests the caller may decide, as a
set for `id in (select ...)` in policies and for `list_approvals`. It calls `approval_eligible`, so
the two agree, and a pgTAP file checks that for each user. `sql upgrade` writes the function.
