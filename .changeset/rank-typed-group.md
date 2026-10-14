---
"better-supabase": patch
---

`move()` in the `rank` module now writes the group column as its own type, so a board grouped by a `uuid` stage id or an enum column moves rows instead of failing with `column ... is of type uuid but expression is of type text`. `sql sync` rewrites the rank module.
