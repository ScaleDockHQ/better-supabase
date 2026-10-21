# 0050: Lint unapplied migrations for locking statements in doctor

- Status: accepted
- Date: 2026-10-19

## Context

`apply --preset` and `sql sync` write migrations that alter tables already
holding rows. Some statements lock a table for as long as they scan or rewrite
it: an index built without `concurrently`, a constraint validated in the same
step, a type change, a volatile default. On a busy table that stalls the app
during a deploy. Tools like squawk and strong_migrations catch these before
they ship, but adding one means a second binary or a Ruby runtime, and they
don't know which migrations already ran in a Supabase project.

## Decision

Doctor gets six rules, BS229 to BS234, in `src/cli/doctor/migration-safety.ts`.
They split each migration with `splitStatements` (`src/cli/doctor/shared.ts`),
which skips comments and respects quotes and dollar quotes, and match each
statement with a regular expression. Tables a migration creates are exempt.
BS235, added in 0.13, flags a `better_supabase` function a migration drops
without creating it again with the same number of arguments, the change a
schema diff makes when a release changes a function's signature.

The rules check only migrations that haven't run. With `--db-url`, that is
the files missing from `supabase_migrations.schema_migrations`. Offline, it is
the files after `doctor.migrationSafety.since`, or the newest file when
`since` is unset. `init` and `adopt` set `since` to the newest migration, so
an existing project isn't flooded with findings about history.

## Alternatives considered

Parsing with `libpg_query` gives an exact syntax tree, but it is a native or
WebAssembly dependency of several megabytes for a CLI that inlines its
dependencies (ADR 0007). Running squawk as an optional peer would cover more
cases, but it needs a separate install and still can't tell which migrations
ran. Checking every migration in the folder reports statements that ran years
ago and can't be changed (a pushed migration is never edited).

## Consequences

The checks catch the common locking statements without a new dependency. The
regular expressions can miss unusual syntax, such as a statement built in a
`do` block, and can't tell a binary-compatible type change from one that
rewrites, so BS231 can over-report; `doctor.ignore` silences a code. If the
rules need a real parser, revisit `libpg_query` behind a lazy optional peer.
