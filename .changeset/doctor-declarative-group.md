---
"better-supabase": minor
---

`doctor` analyzes the files under `supabase/schemas` with pg-topo and needs no database: BS720 (a file does not parse), BS721 (an object no file creates), BS722 (two statements create the same object), BS723 (a dependency cycle) and BS724 (an invalid `-- pg-topo:` annotation). Under pg-delta it also reports BS725 (a `do` block with DDL, `cron.schedule` in a function body, `alter publication` through `execute`, default privileges without `for role`), BS726 (the reserved names `_cluster` and `_custom`), BS727 (`schema_paths`), BS728 and BS729 (`_custom/` files without a migration or with modeled objects) and BS730 (a published table without a replication key).
