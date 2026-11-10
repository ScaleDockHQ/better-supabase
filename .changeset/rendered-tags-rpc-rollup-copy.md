---
"better-supabase": minor
---

Three more `@bsb` tags render SQL through `better-supabase table <name> enable <tag>`: `rpc` writes `get_<table>_by_ids(ids)`, which returns rows in the order of the ids, `rollup stored` writes a trigger that keeps a count or a sum on a parent row, and `copy` writes `copy_<table>(source)`, which inserts a copy of one row. Each is written between `-- @bsb-tag <name> begin` and `end` markers, so a second run replaces it. See [Tags that render SQL](https://bettersupabase.com/docs/repository/rendered-tags).
