# 0431: `gen --offline` reads only the saved snapshot

- Status: accepted
- Date: 2026-11-09
- Amends: 0291

## Context

`gen --check` reads the database unless a snapshot is configured or given. In CI
a job that only wants to know whether the generated files are current could still
open a connection when `source.snapshot` was missing, and fail late with a
connection error.

## Decision

`gen --offline` never connects. It needs `--snapshot <file>` or `source.snapshot`
and fails with a usage error naming both when neither exists. It refuses
`--db-url-stdin` and `--project-ref`. It works with `--check`, `--dry-run` and a
plain run.

## Consequences

No module is rewritten and no data migration is needed. Unit tests cover the
missing snapshot, a live flag and a generation from a given snapshot; the help
snapshot and `cli/gen.mdx` list the flag.
