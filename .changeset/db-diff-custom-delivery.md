---
"better-supabase": minor
---

`db diff` lists the `supabase/schemas/_custom` files that no migration delivers, in the log and in `data.custom`: a file with no `-- pgdelta-migration:` line, or one that names a migration that does not exist.
