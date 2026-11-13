# 0844: Index search once per import run, through statement triggers

- Status: accepted
- Date: 2026-11-13
- Supersedes: the part of [0421](0421-search-defers-indexing-during-imports.md) that rejected a table

## Context

ADR 0421 deferred search indexing to the end of each `import_upsert_batch`,
with the dirty keys in transaction-local settings. A run of many batches that
touched the same records indexed each record once per batch. The row-level
index trigger also ran once per written row, so a set-based batch target such
as `public.import_customer_batch` still paid one trigger call per row.

The batch target also never received `subjectId`, which its contract
promises, so an update batch inserted duplicates, raised, and fell back to
one `write` call per item.

## Decision

- `search_enqueue` notes a key in `better_supabase.import_search_dirty
  (run_id, subject_type, subject_id)` while `better_supabase.search_deferred`
  is on and `better_supabase.import_run` is set. `finish_import_run` and
  `cancel_import_run` call `search_refresh_run(run)`, which indexes each
  noted record once and deletes the notes. `import_upsert_batch` no longer
  calls `search_refresh_dirty`. A dry run rolls its writes back, notes
  included.
- `recordTypes.<type>.search.statement: true` replaces the row trigger with
  three statement triggers (`bsb_search_<type>_insert`, `_update`,
  `_delete`) on `search_index_stmt`, which reads the ids from the transition
  tables and passes them to `search_enqueue_many`. Postgres doesn't allow
  `update of <columns>` with transition tables, so the update trigger
  compares the watched columns itself. Row triggers stay the default.
- `import_apply_batch` adds `subjectId` to each item it hands a batch target.
- The fixture's `customers` type sets `search.statement`.

## Alternatives considered

- Keep the settings and refresh at the end of each batch (ADR 0421): a
  record written by three batches is indexed three times.
- An unlogged notes table: a crash would drop the notes and leave records
  unindexed until the next write.
- A purge for abandoned runs: the imports module has no purge, and dropping
  notes would leave written records unindexed. A run that never finishes or
  is cancelled keeps its notes.

## Consequences

Module versions: search 4, imports 3. A record written by a running import is
searchable only once the run closes. The scale test (`scale_import_batch`)
runs three batches of 1,000 customers: 6 `search_index_stmt` calls and 1,000
`search_refresh` calls, all in `finish_import_run`. Switching a type between
row and statement triggers renames its triggers and needs a migration.
