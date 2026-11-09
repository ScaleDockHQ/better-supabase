---
"better-supabase": minor
---

Two batches of one import run no longer wait on each other. `import_upsert_batch` reads the run without `for update`, and only the counts update at its end locks the run row. `imports.run` also adapts its batch size: a batch over `targetBatchMs` (default 30,000) halves the next one, `maxBatchSize` lets fast batches double it, a batch that hits the statement timeout is split in two and sent again, and the result carries `suggestedBatchSize`.

`better-supabase upgrade` rewrites the `imports` module and no data migration is needed.
