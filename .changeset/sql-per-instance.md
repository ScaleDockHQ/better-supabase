---
"better-supabase": minor
---

Each block instance renders its own SQL. A second instance writes files
named after it, prefixes the table, function, trigger and index names its
entity renames leave unchanged with the instance name, reads the dependency
instance its `uses` names, and records itself in `better_supabase.blocks`
with the new `block` column. Its block marker names the block, the default
roles grant its renamed permission keys, and `doctor` and `upgrade` track
each instance's version.
