# 0439: Record the mapper version of a run and expose the record map's hashes

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

When an import's mapping code is fixed, the records it already wrote keep their old
content hash, so a rerun of unchanged source data reports them unchanged and never
rewrites them. There was also no way to read the record map's hashes without selecting
the table.

## Decision

- `import_runs.mapper_version` (text, optional) takes `mapperVersion` from the run's
  start options and is part of the run JSON.
- `reapply_import_records(tenant, source, mapper_version, entity)` clears the hash of
  the source's records whose last run has a different mapper version, so the next run
  rewrites them; a row a user changed since is still protected by the conflict check.
  It returns the number cleared.
- `export_import_hashes(tenant, source, entity)` returns the record map as one object
  per record.
- Both functions are service-role only and run as their caller (no definer function).

## Consequences

`better-supabase upgrade` rewrites the `imports` module and the next schema migration
adds the column and two functions. No data migration: existing runs have no version, so
the first `reapply_import_records` with a version clears every record of the source
that is not at that version, which is the intent after a fix. pgTAP
`import_mapper_version` covers the version, the clear, the rewrite and the export.
