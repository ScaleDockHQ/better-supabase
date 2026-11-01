---
"better-supabase": minor
---

Postgres features are now opt-in. `searchColumn` on `contacts`, `deals`, `tasks`, `invoices` and `drive`, and the `@bsb search` table tag, add a stored `search_tsv` column with a GIN index. `noOverlap` on `leases`, `calendar` and `passes` adds exclusion constraints. `partitioned` on `field-history` partitions `field_changes` by month. `better-supabase doctor` gains BS360 for secret-named columns outside Vault.
