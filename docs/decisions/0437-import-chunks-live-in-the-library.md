# 0437: Store import chunks in the library and process them from the queue

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

`enqueue_import_chunks` queued one job per chunk number, but the items of a chunk
lived in an app table (`public.import_chunks`) with app functions to claim and
finish them, plus an app worker. Every app that imported at scale rewrote that
runner, and a chunk could be written twice when a job was retried.

## Decision

- The imports module owns `import_chunks`: one row per `(run, entity, chunk)` with
  its items, a status (`pending`, `claimed`, `done`), what its batch answered and the
  claim time. It belongs to the tenant, is not exported, goes with its run
  (`on delete cascade`) and with a tenant purge (the data-lifecycle module lists it),
  and is closed to every API role.
- Service-role functions: `store_import_chunk` (replaces a pending chunk, leaves a
  done one), `claim_import_chunk` (`for update skip locked`, takes over a claim older
  than `lease` seconds), `complete_import_chunk`, `process_import_chunk` (claim, write
  with `import_upsert_batch`, complete, in one transaction) and
  `import_chunk_progress`.
- TypeScript: `imports.chunks.{store, process, progress}`, `importChunkSchema` for the
  `imports` queue, `importChunkHandler(imports)` for any queue runner and
  `runImportWorker({ imports, queue, concurrency, signal })`, which calls the queue's
  `work` on the `imports` queue.

## Consequences

`better-supabase upgrade` rewrites the `imports` and `data-lifecycle` modules and the
next schema migration creates the table and five functions. No data migration. An app
that kept its own `public.import_chunks` can drop it once it calls the library
functions; the app's runner functions and `import_claim_chunk` become removable.
pgTAP `import_chunks` covers store, replace, claim, stale claim, process, a done chunk,
a failure that leaves the chunk pending and the closed table; unit tests cover the
client, the handler and the worker.
