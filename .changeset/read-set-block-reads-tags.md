---
"better-supabase": minor
---

Block reads in a read set know their tables and schema. `blockRead` takes the tables the function reads and the block's API schema, so `s.blocks.deals.board(...)` compiles against the right function without it being in your schema metadata, and `bsb.tags(readSet)` tags a `"use cache"` scope with those tables. `bsb.blockAction` takes `invalidates` (for example `reads.deals.board.tables`) to drop the tagged entries after a successful write. `readSetTables` includes the tables of a block read.
