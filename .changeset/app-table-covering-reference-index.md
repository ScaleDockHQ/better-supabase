---
"better-supabase": patch
---

An app table's reference to a tenant-scoped table is a foreign key on `(tenant, column)`. Its index now covers both columns, `(column, tenant)`, instead of `(column)` alone, so the foreign key checks and joins read an index and the Performance Advisor no longer reports the key as unindexed. Run `better-supabase upgrade` and generate the migration; the old single-column index is dropped.
