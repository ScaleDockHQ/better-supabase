---
"better-supabase": minor
---

`better-supabase/sql` adds `parseBsbComment`, `formatBsbComment`, `setBsbTag` and `commentOnTableSql`, which read and write the `@bsb` feature tags in a table comment (ADR 0102). Nothing reads them yet; `gen` and the `table` command follow.
