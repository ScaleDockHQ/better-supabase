# 0215: Enum value removal goes through a new type, and backfill edits array elements

- Status: accepted
- Date: 2026-11-03

## Context

Postgres has no `alter type ... drop value`. A schema diff that removes a value
from an enum plans a type drop and create, which fails once a column uses the
type, and `delete from pg_enum` corrupts stored data. Removing the value also
needs the rows that hold it, often inside a jsonb array, to change first.
`db backfill` filled columns only.

## Decision

Doctor reports `alter type ... rename value` and `delete from pg_enum` in an
unapplied migration as BS240. The docs describe the steps: create the new
type, move the column with `alter column ... type ... using`, then drop the old
type. `tests/integration/enum-value-removal.integration.test.ts` runs pg-delta
against the stack and keeps the described plan true.

`db backfill <table.column> --array <path> --match <json>` changes the elements
of a jsonb array: `--delete` removes the elements that contain the match and
`--merge <json>` merges an object into them. It runs in `ctid` batches like the
fill mode, and `--dry-run` prints the number of rows and elements it would
change. The array mode excludes `--from` and `--value`.

## Alternatives considered

A doctor rewrite of the migration hides the cost of the data change. Raw SQL in
the migration locks the table for the whole update, which batches avoid.

## Consequences

An enum change is a three-step migration with a backfill in between. BS240
takes BS236's place from the plan, since BS236 was already in use.
