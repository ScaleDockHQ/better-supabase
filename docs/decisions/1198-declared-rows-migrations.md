# 1198: Turn supabase/rows into hash-stamped data migrations

- Status: accepted
- Date: 2026-11-22

## Context

Declared defaults (ADR 1197) are rows, and a rows file must reach the database
the same way on every machine. A schema diff never captures rows, a migration
that was pushed must not change (hard rule), and a rows file has to be easy to
review.

## Decision

The folder `supabase/rows` holds `.sql` files of upserts, and the command
`better-supabase db rows` writes a data migration for each file whose statements
changed. A migration carries `-- @bsb-rows <file> sha256:<hash>`, where the hash
covers the statements without comments and whitespace. The command compares the
file's hash with the newest migration that carries its name, and writes a new
migration only when they differ, so an existing migration is never rewritten.
`--check` exits 1 instead of writing, for CI, and `--dry-run` prints the plan.

The reader (`src/cli/rows/read.ts`, on the pg-parser statement list) accepts
only `insert ... values ... on conflict (<key>) do update`. It refuses `do
nothing`, a missing conflict target, a select source, `returning`, a `with`
clause, a subquery, a key that is not a literal and any function call except
`jsonb_build_object`, `jsonb_build_array` and `to_jsonb`. A row removed from a
file stays in the database and the command prints a `review:` line, because a
migration cannot know whether the app changed the row. A file that carries
`-- bsb-rows: delete-removed` makes the migration delete removed rows by their
natural key.

## Alternatives considered

Running the files directly against the database: no history and no review.
Rewriting the last migration: breaks the rule about pushed migrations. Deleting
removed rows by default: it can destroy rows the app edited.

## Consequences

A data change is one reviewed migration with a hash that proves where it came
from. Only upserts are allowed, so a rows file cannot express a one-off data
fix; that stays a hand-written migration.
