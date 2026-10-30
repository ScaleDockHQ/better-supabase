---
"better-supabase": minor
---

Imports keep an external record map, so a rerun inserts new keys, skips unchanged ones, updates
changed ones and leaves a row a user edited alone. This is a breaking change to the import run
table and its client.

`import_runs.kind` is now `source`, and a run has the status `canceled`, the flags `dry_run` and
`full`, `input_checksum`, `correlation_id`, `scope_aliases`, `started_at` and `finished_at`. `counts`
is `{ <entity>: { inserted, updated, unchanged, conflicted, missing } }` and `errors` is `[{ entity,
key, code, message }]`. Only one run per tenant and source can be pending or running; a second
`start` fails with `IMPORT_RUN_ACTIVE`. The new table `import_records` maps `(tenant, source, scope,
entity, external key, role)` to the subject it imported.

The imports client gains `runs.start`, `runs.get`, `runs.list`, `runs.cancel`, `markRunning`,
`upsertBatch`, `resolve` and `finish`. `import_upsert_batch` writes each item through an import
target, hashes `data` to decide between unchanged and changed, reports `conflicted` for a row
changed after the last import, reuses a scope alias's record and, for a dry run, rolls back and
returns the counts. `finish` marks the records a full run did not send as missing and never
deletes them, and it emits `import.entity_completed` for each entity. A block contributes a target
through the new `imports` contribution kind (`{ entity, subjectType, write, updatedAt? }`), and an
app lists its own in `blocks.imports.options.targets`. The hint codes are `IMPORT_RUN_ACTIVE`,
`IMPORT_RUN_NOT_RUNNING`, `IMPORT_TARGET_UNKNOWN` and `IMPORT_ITEM_INVALID`.

`defineImport` and `appTableImport` take `source` instead of `kind`, and `defineImport` takes an
optional `target` that `runImport` writes through `hooks.upsertBatch`. Run `better-supabase codemod
0.47` to list the code to rename, then `better-supabase upgrade` and generate a migration. The
migration guide from 0.46 to 0.47 has the table of changes.
