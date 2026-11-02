---
"better-supabase": minor
---

Read sets take block reads and record summaries. `defineReadSet(db, name, { blocks: reads }, ...)` adds `s.blocks.<instance>.<read>(args)` for the reads the installed blocks ship, and `s.record(type, id, { sections })` adds the record summary. Both run inside the single `rs_<name>` round trip, as the caller.
