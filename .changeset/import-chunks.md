---
"better-supabase": minor
---

Large imports run in chunks from the library. The imports module has an `import_chunks` table and the service-role functions `store_import_chunk`, `claim_import_chunk`, `complete_import_chunk`, `process_import_chunk` and `import_chunk_progress`; `imports.chunks.{store, process, progress}`, `importChunkSchema`, `importChunkHandler` and `runImportWorker({ imports, queue })` drive them from the `imports` queue. `process` writes a chunk once even when its job is retried, a failure leaves the chunk pending, and a claim older than five minutes is taken over.

`better-supabase upgrade` rewrites the `imports` and `data-lifecycle` modules and the next schema migration creates the table and functions. No data migration is needed. An app's own chunk table and runner functions become removable once it calls these.
