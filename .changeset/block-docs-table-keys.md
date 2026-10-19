---
"better-supabase": patch
---

The number-sequences and teams docs name the adopt-mode table keys the blocks read: `tables.sequences` (not `tables.numberSequences`) and `tables.members` (not `tables.teamMembers`). A unit test now checks every `tables.*` and `columns.*` key on the blocks pages against the block's SQL modules.
