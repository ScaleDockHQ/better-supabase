---
"better-supabase": patch
---

`bsb.cached({ keep: { tables } })` keeps a stable function call and a `db.$many()` batch as one entry, tagged with those tables. A volatile function still reaches the database, and a failed call is not stored. A function the schema does not name is kept when the tables are listed, so a block read and `read_batch` can be kept too. Doctor rule BS609 also names `read_batch` and `bsb.record(type).get` next to the read set.
