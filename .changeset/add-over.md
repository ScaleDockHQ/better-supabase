---
"better-supabase": minor
---

`better-supabase add <block> --over <schema.table>` installs one block over a table you already have. It proposes the `tables` and `columns` mapping, reports what cannot map and writes `blocks.<block>` to the config, like `add --adopt <block> --tables`, and refuses to combine with those two flags.
