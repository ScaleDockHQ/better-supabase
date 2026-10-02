# 0006: Diff the fixture schema with pg-delta; the native stack stays opt-in

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

The native stack is not committed. Agents and sandboxes without Docker opt in
with `SUPABASE_EXPERIMENTAL_STACK=1`; CI and everyone else run the Docker
backend. `better-supabase env` reads `supabase status --env` when the native
stack rejects `supabase status -o json`, so consumers who turn it on keep a
working `env`.

## Alternatives considered

- Stay on migra: `schema_paths` ordering and the hand-added grants in every
  migration would keep diverging from what new Supabase projects do.
- Commit `[experimental] stack = true`: on CLI 2.119.0 the native stack's
  Realtime refuses or times out private-channel joins that the Docker backend
  accepts (the Realtime kit and PermDock topic integration tests), so the CI
  `stack` job would fail.

## Consequences

Schema changes no longer need the stack stopped, and file order in
`supabase/schemas` no longer matters. pg-delta is experimental in the Supabase
CLI, so a CLI bump can change generated migrations; review them. Revisit the
native stack when a CLI release passes `pnpm test:integration` with
`SUPABASE_EXPERIMENTAL_STACK=1`; then commit `stack = true` and switch CI and
`scripts/env-local.ts` to `supabase status --env`, which the Docker backend
rejects.
