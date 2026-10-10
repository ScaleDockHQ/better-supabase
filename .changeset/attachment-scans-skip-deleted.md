---
"better-supabase": patch
---

The attachment scanner's `sink()` and `job` no longer fail for an attachment that was deleted before its scan. A missing attachment made the sink throw, so the outbox relay retried the whole batch until it dead-lettered it and every later event for that consumer waited behind it. The sink now skips that event and the job completes; download, transport and `scan` errors still throw and retry. The object scanner does the same for an object deleted from storage (`NoSuchKey`), while a missing bucket still throws. `scanner.scan()` and `objects.scan()` keep returning the `not_found` error.
