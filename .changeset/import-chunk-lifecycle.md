---
"better-supabase": minor
---

Breaking: a done import chunk drops its items and keeps its result, and `runs.finish` refuses a
run with a chunk that is not done (`IMPORT_CHUNKS_OPEN`). `importChunkHandler` marks the chunk
and its run failed on the job's last attempt (`fail_import_chunk` gains `final`), and
`maintenance()` clears the items of ended runs after `chunks.keepFailedItems` (default 7 days)
and, with `chunks.staleAfter`, cancels a run whose worker died. `runs.get` reports chunk counts
and bytes, `runs.conflicts` pages every conflict of a run, and a stock count without a location
goes to the organization's only active one. The chunks of a done 50,000-item run took 839,540
bytes and take none now (ADR 1223).
