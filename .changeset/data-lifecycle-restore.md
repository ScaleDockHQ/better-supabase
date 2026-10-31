---
"better-supabase": minor
---

`createDataImporter` in `better-supabase/blocks/data-lifecycle` restores an organization export. It
reads the NDJSON-per-table files, checks table and column names against `data_lifecycle_tables()`,
and writes each row through the `imports` record map in import mode with `source = 'restore'`, so a
second restore of the same files writes nothing. `dryRun` returns a per-table report with unknown
tables, unknown columns, row counts and conflicts. CSV exports are refused with a typed error
because they are lossy. The `data-lifecycle` module adds `data_restore_tables` and
`restore_data_row` and registers the `data_lifecycle_row` import target. Run
`better-supabase upgrade` and apply the new migrations.
