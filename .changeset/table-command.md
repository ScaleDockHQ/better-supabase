---
"better-supabase": minor
---

`better-supabase table <table> enable|disable <feature>` turns a per-table feature on or off by editing the `@bsb` tag in the table comment, in the schema file that creates the table (ADR 0102). It takes `--dry-run` and `--check`. `better-supabase/sql` exports `TABLE_FEATURES`, `setTableFeature` and the helpers behind it.
