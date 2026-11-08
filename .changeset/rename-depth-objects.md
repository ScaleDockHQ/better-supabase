---
"better-supabase": minor
---

`renameBlock` follows a renamed client four object levels deep and no longer counts functions, promises and results as levels, so the types instantiate two levels earlier with the same result for every block. `better-supabase upgrade` rewrites no module and no data moves; a block type with more than four nested object levels below its methods keeps its original keys at the fifth.
