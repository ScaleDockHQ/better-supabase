# 0687: Squash the fixture migrations again

- Status: accepted
- Date: 2026-11-12
- Follows: [0027](0027-fixture-pgdelta-baseline.md)

## Context

Since the reset in 0027 the history grew to 679 migrations and 96 MB. Every
`supabase db reset` replays all of them, and every new worktree stack pays
that cost, which is the slowest step of an agent session that needs a
database.

## Decision

The history is reset to eight migrations:

1. `better-supabase sql sync` writes the extensions.
2. `supabase db squash` writes the baseline of `supabase/schemas` (13 MB).
3. `fixture_data.sql` keeps what a diff skips (RBAC role permissions,
   buckets, the PostgREST setting).
4. `better-supabase add --adopt` run in `apps/examples/nextjs` writes the
   module rows.
5. Three migrations that the squash does not carry, written by hand:
   `workflow_schema.sql` holds the `workflow` schema of the Workflow SDK world with the
   trigger the schema files declare on it, `permission_catalog.sql` holds the permission catalog and the default role
   grants that the old module data migrations inserted, and
   `managed_schema_objects.sql` holds the policies on `realtime.messages` and
   the triggers on `auth.users`, because a schema diff skips the schemas
   Supabase manages. Both lists come from the old database, so the result
   matches it.

A reset from the new history passes the whole pgTAP suite on the library seed
(4,501 tests, the same count as before) and gives the same policies,
triggers and functions on `auth`, `storage` and `realtime`. The exported
schema differs only in column order for columns that old migrations added
with `ALTER TABLE`.

## Consequences

This is the second exception to "never change a pushed migration", safe for
the same reason as in 0027: only local stacks and CI apply this history.
After pulling it, run `pnpm supabase:reset`. The next squash needs three
checks: the schemas no declarative file owns, the managed schemas and the
permission catalog. CI's schema drift check catches the first.

## Baselines

The Next.js server baselines rose by about 80 bytes of raw JavaScript per route after the squash, with the turbo, Supabase CLI and Next.js bumps in the same branch. The baselines were raised once by hand in `tests/next-build/server-baseline.json`; the update command still never raises one.
