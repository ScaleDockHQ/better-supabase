---
"better-supabase": minor
---

The tenant module checks that references stay inside one tenant. `sql.modules.tenant.options.sameTenant` lists `{ table, column, references, tenant? }` entries, where `references` is a table or `{ table, column?, tenant?, where? }`, and the module puts a `bs_same_tenant_<column>` trigger on each table that calls one generic `better_supabase.same_tenant()` function. An insert, or an update of the column or the tenant column, that references a row of another tenant (or one outside `where`) fails with `TENANT_MISMATCH` (SQLSTATE `23514`) for every writer, the service role included. Apps no longer need a hand-written scope trigger per child table. The access docs also describe composite foreign keys as the trigger-free alternative.
