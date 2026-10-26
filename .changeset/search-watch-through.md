---
"better-supabase": minor
---

`config.records.<type>.search.watch[]` takes `through: [{ table, from, to }]`, which follows the watched row's `key` across further tables, such as a junction table, before it reaches the record's id (or the record's `via` column). Renaming a tag can now re-index every record it is linked to.
