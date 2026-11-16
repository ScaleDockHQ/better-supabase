---
"better-supabase": patch
---

`add --adopt` writes a block's data statements again when an upgrade step
since the version an earlier data migration recorded asks for it. The search
2 to 3 upgrade does, so the adopted migration carries `search_reindex()` again
and existing documents get their `facets` and `sort_key`.
