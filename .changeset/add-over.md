---
"better-supabase": minor
---

`better-supabase add <block> --over <schema.table>` installs one block over a table you already have. It reads the schema (the snapshot, or `--db-url`), proposes the `tables` and `columns` mapping, and writes `blocks.<block>` to the config. It is the short form of `add --adopt <block> --tables <schema.table>`, and it refuses `--adopt`, `--tables` and more than one block.
