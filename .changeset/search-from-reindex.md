---
"better-supabase": patch
---

A record type whose search reads `from` a view now re-indexes on any update of the record's row, so renaming a record or setting its archived flag updates its search document. Before, only the id, tenant, `deletedAt` and `url` columns were watched.
