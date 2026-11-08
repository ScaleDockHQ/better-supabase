---
"better-supabase": minor
---

`enqueue_import_chunks` puts its jobs on the queue `imports`. The name was passed with its own quotes, so the jobs went to a queue that no worker reads. `better-supabase upgrade` rewrites the `imports` module. No schema data migration is needed, but a chunk job queued under the quoted name before the upgrade stays there, so call `enqueue_import_chunks` again for a run that still has unprocessed chunks.
