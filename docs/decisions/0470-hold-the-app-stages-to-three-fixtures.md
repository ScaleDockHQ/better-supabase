# 0470: Hold the app stages to three fixtures

- Status: accepted
- Date: 2026-11-08

## Context

Part 10 of the declarative base layer plan names four app stages: a new app, an
existing app on the adoption ladder, an app on each of the three SQL workflows,
and an app with no tenants. Only `validation-declarative` and
`validation-lienlink` existed, and both are B2B apps on pg-delta. An audit
found the three fixtures the plan lists for the other stages missing, and
writing them found three gaps.

## Decision

`tests/validation-new-app` runs `init --yes` in a new app for each framework
`init` detects (Next.js, Hono, Expo, Vite, SvelteKit, TanStack Start, React
Router) and each package manager. It asserts that the config is short and names
no tenant, that no file of the app changes, that the printed commands use the
detected package manager, then that `gen` runs from a snapshot and the
generated core typechecks with no edit.

`tests/validation-migrations` runs `upgrade` on the declarative fixture's
tables under `migrations` and `migra`, where an earlier migration creates the
tables. Under `migrations`, one migration is written with a content hash, a
stamp after the newest migration (even one dated ahead of now), no module
file, no table the app already has, and nothing on a second run. A changed
config writes a second migration. Under `migra`, the module files land in
`supabase/schemas` and no migration is written. Under `pg-delta`, no migration
is written. Doctor's ownership rules pass under both, and on a Lite project.

`tests/validation-single-tenant` is a B2C app with `profiles` and `sessions`
and an owner-policy table. No generated file names a tenant, an organization,
a membership or a team.

The gaps the fixtures found:

- Under `migra`, `upgrade` forgot the app's tables once its own files sat in
  `supabase/schemas`, because it read only that folder, and a second run wrote
  `create table` for them. It now reads the schema files and the migrations for
  every workflow except pg-delta.
- `init` added `[experimental.pgdelta]` to a `supabase/config.toml` that lists
  `[db.migrations] schema_paths`, which switches a migra project to pg-delta.
  It now skips the edit and says how to move.
- `profiles` added `active_organization_id` and `active_team_id` to every app.
  It adds them only next to `memberships` and `teams`, or when the app maps
  the column.
- The generated module imported `EnrichDatabase` when no table needed it, which
  fails `noUnusedLocals`.

## Consequences

The three fixtures run in `pnpm test` without the Supabase CLI or Docker. They
read no database: `new-app` gives `gen` a snapshot of an empty Supabase
database. Doctor's schema coverage rules (BS376 and BS377) stay with
`validation-declarative`, which holds a baseline migration.

`notifications` and `audit` keep a nullable `tenant_id` and a prelude helper
for the tenant, so the single-tenant fixture doesn't use them. A tenantless
mode for both is open work.
