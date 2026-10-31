# 0141: Import through an external record map and an import mode

- Status: accepted
- Date: 2026-10-30

## Context

The `imports` module (ADR 0029) is a run log: `import_runs` holds a kind,
a status, a mapping, counts and errors, and `start_import` and `finish_import`
open and close a run. Deduplication happens in TypeScript (`defineImport`,
`appTableImport`), so a second run of the same input can write again, and
nothing records which source key became which row. Moving an organization from
a legacy system needs the opposite: the same input twice writes nothing, a
newer input changes only the records that changed, a record a user edited
afterwards is reported instead of overwritten, and a migration does not fire
workflows, webhooks, stock movements or audit rows for every historical row.
Drive sync (`drive_sync_batch`) already solves a small version of this with a
`(drive, source, external_id)` key and no content hash.

## Decision

- **A record map.** `import_records` keeps one row per
  `(tenant_id, source, scope, entity, external_key, role)` with the subject it
  became, a content hash, the first and last run that saw it and a
  `missing_since` marker. `role` lets one source record map to several
  subjects. `scope` separates administrations of the same source and defaults
  to an empty string.
- **Targets by contribution.** A new contribution kind `importTarget` in
  `sql/contributions.ts` registers `{ entity, subjectType, write }`. Blocks add
  targets in their own PRs, and app tables get a generic one from their config.
  `import_upsert_batch(run, entity, items)` is the single write path: an
  unknown key inserts, an equal hash counts as `unchanged` and writes nothing,
  a changed hash updates unless a user changed the row after the last import,
  which counts as `conflicted` and leaves the row alone. Dry runs roll back to
  a savepoint and return counts only. A scope alias lets a cloned
  administration reuse the subjects of another scope when the hash matches.
- **Runs reshape (breaking).** `import_runs.kind` becomes `source`, with
  `dry_run`, `full`, `input_checksum`, `correlation_id`, `scope_aliases`,
  timestamps and per-entity counts. One active run per organization and
  source, enforced by a partial unique index and a lease. A full run marks
  missing keys and never deletes.
- **Import mode.** `better_supabase.begin_import_session(run)` is service only
  and sets a transaction-local run ID. `better_supabase.import_run()` returns
  it only for `service_role`, so a user session can't turn the mode on. In the
  mode the outbox skips or tags events (`imports.events`), row audit is
  tagged `integration` with the run's correlation ID or reduced to one summary
  event (`imports.audit`), the state machine accepts any declared status on
  insert and writes one history row with the reason `imported`, and a new
  `ctx.importing()` guards stock consumption, ledger and `accounting` posting,
  notifications, workflows and webhooks. Every SQL function that writes reads
  `import_run()`.
- **Drive sync writes the map.** With the `imports` block installed,
  `drive_sync_batch` keeps its signature and records every mirrored node in
  `import_records` (`source = 'drive:<connection>'`, `entity = 'drive_node'`,
  `scope = <drive id>`) with a hash of what the provider sent. A node whose
  hash is unchanged is not written, so the function returns the number of
  nodes written, and a full listing finds the nodes it did not reach through
  the record's `last_run_id` (a run ID derived from the connection and the
  `sync_run` text). `blocks.drive.options.sync.prune` is `delete` (the
  default: unlisted nodes are deleted, and a legal hold keeps its node) or
  `mark` (unlisted nodes stay and their record gets `missing_since`, cleared
  when they return). Without the `imports` block drive keeps its earlier
  behavior: every listed node is upserted and stamped with `sync_run` in its
  metadata, and `prune: 'mark'` is refused at render time, because the mark
  has no place to live. A drive-local copy of the record map was rejected: it
  would duplicate `import_records` for no gain, and the `imports` block is the
  one place that records which external key became which row.

## Alternatives considered

- **Keep deduplication in TypeScript.** Each importer would need its own key
  table, and the audit and side effect problems would stay unsolved.
- **A column `external_id` on every table.** It can't hold several sources,
  scopes or roles per row, and it changes every block table.
- **Disable triggers during import.** It skips guards that must still run
  (tenant scope, constraints) and needs a privilege no app should hold.

## Consequences

- A repeated import is cheap and visible: counts per entity, a conflict list
  and no audit rows for unchanged records.
- Breaking for anything reading `import_runs.kind` or `counts`; the upgrade
  guide and a codemod step cover it.
- Every new write path has to honor `ctx.importing()`; the docs list each
  guarded hook. Revisit the hash rule if a target needs field-level merging.

## Import mode as built

`import_upsert_batch` begins the session itself and restores the caller's
settings when the batch ends; a worker that runs chunk jobs calls it per
chunk. `imports.events` defaults to skipping every event and `imports.audit`
to `rows`. The guards cover the side effects that a write triggers by itself
(outbox events, notifications, accounting auto-posting, stock taken for paid
orders and shipped shipments). Explicit stock and ledger calls are not
guarded, because an importer calls them on purpose with source balances. The
docs page lists each guarded hook.

## Data lifecycle restore as built

`createDataImporter` (`better-supabase/blocks/data-lifecycle`) reads the
NDJSON-per-table organization export and writes it through the record map
with `source = 'restore'`. `data-lifecycle` contributes one import target,
`data_lifecycle_row`, whose write function `restore_data_row` inserts a row
into the importing organization (it replaces the tenant column and updates by
primary key, and refuses a key owned by another organization). Table and
column names are checked against `data_restore_tables()`, which derives from
`data_lifecycle_tables()` and the catalog; a row's key is its primary key
values, or a hash of its line for a table without one. The CSV export is
lossy (null and empty text coincide, formula guards, untyped JSON), so the
importer rejects it with `DATA_RESTORE_CSV` instead of guessing. The target
has no `updatedAt` reader, so a changed row overwrites a user's edit; the
restore is for rebuilding an organization, not merging into a live one.
