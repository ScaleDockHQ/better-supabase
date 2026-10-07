---
"better-supabase": minor
---

`sql.modules.tenant.options.sameTenant` entries take `match: { <column>: <referencedColumn> }`, so the referenced row must also hold the same value as other columns of the row being written, for example an asset that must belong to the job's customer. The `bs_same_tenant_<column>` trigger also fires on updates of the `match` columns, and `better_supabase.same_tenant()` compares each pair with `is not distinct from` for every writer. A mismatch fails with `TENANT_MISMATCH` (SQLSTATE `23514`). Existing entries render the same trigger as before.
