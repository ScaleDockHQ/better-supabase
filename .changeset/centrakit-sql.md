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
