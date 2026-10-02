# 0006: Diff the fixture schema with pg-delta and run the native local stack

- Status: accepted
- Date: 2026-10-02

## Context

The local stack in `supabase/` is the fixture every example, integration test
and codegen run uses. Its migrations came from the legacy migra engine, which
read `supabase/schemas` in the order `[db.migrations] schema_paths` listed,
only while the stack was stopped, and missed grants, comments and the
Postgres 17 `MAINTAIN` privilege. Supabase CLI 2.119.0 ships pg-delta as the
declarative diff engine (Declarative Schemas 2.0) and a native local stack
that runs without a Docker daemon, one stack per checkout. New projects from
`supabase init` use pg-delta by default, so the projects better-supabase
supports are moving to it.

## Decision

`supabase/config.toml` sets `[experimental.pgdelta] enabled = true` with
`declarative_schema_path = "./schemas"` and drops `schema_paths`; pg-delta
orders the files by dependency. Migrations come from
`pnpm supabase:sync <name>` (`supabase db schema declarative sync --no-apply
--strict-coverage`), and `database.yml` fails when `supabase/schemas` changes
without a migration. The adoption migration
(`20261002204857_pgdelta_adoption.sql`) revokes the `MAINTAIN` privilege migra
had left on `notifications`.

`[experimental] stack = true` puts `supabase start`, `status` and the `--local`
commands on the native stack. Its `status` rejects `-o env` and `-o json`, so
CI and `scripts/env-local.ts` read `supabase status --env`, and
`better-supabase env` falls back to it.

## Alternatives considered

- Stay on migra: `schema_paths` ordering and the hand-added grants in every
  migration would keep diverging from what new Supabase projects do.
- Enable the native stack only through `SUPABASE_EXPERIMENTAL_STACK=1`: CI
  would keep testing the Docker backend, and agents in sandboxes without
  Docker would need a setting the repo doesn't show.

## Consequences

Schema changes no longer need the stack stopped, and file order in
`supabase/schemas` no longer matters. Both features are experimental in the
Supabase CLI: the native stack is alpha, and `SUPABASE_EXPERIMENTAL_STACK=0`
switches one command back to the Docker backend. Revisit when either setting
leaves `[experimental]`, or when the native stack breaks a CI job the Docker
backend passes.
