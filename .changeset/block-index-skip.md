---
"better-supabase": minor
---

`blocks.<name>.indexes.skip` lists `create index` names the module should not create, when the app's own index already covers them. `invoices` can skip `invoices_tenant_status_idx`. A name the module does not create is an error. Doctor BS390 still reports an index that is a prefix of another.

`better-supabase upgrade` rewrites a module whose config sets `indexes.skip`, and the next schema migration drops the skipped index if it was already created. No data migration is needed.
