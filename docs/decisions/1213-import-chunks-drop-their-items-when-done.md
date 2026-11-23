# 1213: Import chunks drop their items when done

- Status: accepted
- Date: 2026-11-23

## Context

ADR 0437 stores an import's items in `import_chunks` so a worker pool shares
the work and a retry never writes a chunk twice. A done chunk kept its items,
so a finished 50,000-item run kept every byte of its input in the table, and a
failed chunk kept them forever (feedback BS-07). A worker that gave up on its
last attempt left the chunk pending, so the run stayed `running`, and
`finish_import_run` closed a run whose chunks were not all written. The summary
listed at most 100 conflict keys, with no way to read the rest (BS-08). A stock
count without a location failed even for an organization with one location.

## Decision

`complete_import_chunk` sets `items` to null and keeps `result`; the column is
nullable and a claim needs items. `finish_import_run` raises
`IMPORT_CHUNKS_OPEN` (PT409) while a chunk of the run is not done.
`fail_import_chunk` gains `final boolean default false`: a final failure also
fails the run, with outcome `failed` and an `IMPORT_CHUNK_FAILED` error naming
the chunk. `importChunkHandler` takes the queue job and calls it with
`final: true` when `job.attempts >= job.maxAttempts`, then rethrows.

`import_chunk_maintenance()` joins `maintenance()` as the housekeeping job
`import_chunks`, every hour. It clears the items of chunks whose run completed
or was canceled, of runs that failed longer than `chunks.keepFailedItems` ago
(default `7 days`), and of failed chunks done longer ago than that. With
`chunks.staleAfter` set, off by default, it also cancels a pending or running
run whose heartbeat is older, with outcome `stale`.

The run JSON gains `chunks: { pending, claimed, done, failed, bytes }`.
`list_import_conflicts(run, entity, after, row_limit)` pages the run's
conflicts by `(created_at, id)`, up to 1,000 a page; `conflictKeys` stays at 100. `import_stock_count` writes a count with no location to the tenant's only
active location. The imports block moves to version 4 and inventory to 6.

## Alternatives considered

A dead-letter sink on the import queue would mark a chunk failed after the
last attempt even when the worker died, but the queue has no sink hook. The
stale-run cancel in maintenance covers a dead worker without one, and the
handler covers every worker that is still alive. Keeping a done chunk's items
for a replay was rejected: the record map and the content hash already make a
second run of the same file cheap. A default location column on inventory was
rejected for the fallback, because the only-active-location rule needs no new
setting.

## Consequences

On the local stack the chunks of a done 50,000-item run took 839,540 bytes and
take none now (`supabase/tests/scale/scale_import_chunk_size.test.sql`).
Breaking: a run with failed chunks can no longer be finished, only canceled or
retried; code that read `items` of a done chunk reads null.
