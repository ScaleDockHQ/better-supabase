# 0108: `db diff` plans with pg-delta's library on the stack's postgres role

- Status: accepted
- Date: 2026-10-26

## Context

ADR 0059 diffed inside the running stack by copying it with `pg_dump` and `psql` into a temporary
database, replacing the managed objects with the schema files, and asking the Supabase CLI to diff
the two. That needed the stack's Postgres binaries, reported no renames or data loss, and could not
stop a migration that drops a table. ADR 0106 decided to use pg-delta's library plan instead.

## Decision

- `better-supabase db diff` plans with `planSchemaFiles` from `@supabase/pg-delta` for a local
  pg-delta project, with `--in-stack`, and when the Supabase CLI cannot start its shadow database.
  The migra workflow and remote databases still run the Supabase CLI.
- `provisionCoLocatedShadow` creates the shadow on the stack's cluster and drops it afterwards.
  `pg_dump`, `psql` and `BSB_PG_BIN` are gone.
- The CLI connects as the stack's `postgres` role, not `supabase_admin`. pg-delta cannot see objects
  that `supabase_admin` owns, so a shadow that role created looks empty and the plan drops every
  table.
- `gatePlan` and `parseRenameHints` (ADR 0106) check the plan. A rename becomes a rename only when a
  migration records `-- bsb: rename old -> new`. A destructive action stops the diff with a
  `check_failed` error unless the user passes `--allow-data-loss`.
- `@supabase/pg-delta` and `@supabase/pg-topo` are optional peers with a tested range, and exact
  devDependencies in the catalog. They are listed in "Pre-release pins". `db diff` says how to
  install them when they are missing.

## Alternatives considered

- Bundle pg-delta in the CLI: `@supabase/*` stays external in the CLI build, and a pre-release
  inside every install is a heavier cost than an optional peer.
- Keep the `pg_dump` copy: it needs binaries the stack may not expose and cannot gate data loss.

## Consequences

The plan can include grants and default privileges that the stack's template database has and the
schema files do not declare. The migration header asks the reader to check the statements before
applying them. Move the pins to stable releases when pg-delta ships one.
