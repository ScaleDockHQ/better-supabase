---
"better-supabase": minor
---

A table comment `@bsb filled-by-trigger created_by owner_id` makes those columns optional on insert in the generated types, the same as `tables.<t>.insertOptional` in the config. A column the config lists too is kept once.

`better-supabase upgrade` rewrites no module and no data migration is needed.
