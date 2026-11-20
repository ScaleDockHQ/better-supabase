# 1096: Start fresh databases from a baseline snapshot

- Status: accepted
- Date: 2026-11-20

## Context

A fresh local or CI stack replays every migration and every seed file. On a
project with 648 migrations, 172 seed files and 348 storage objects, the
default native start took 28 seconds on a laptop (36 seconds in an earlier
run), and CI starts one stack per test shard. Hosted projects apply the same
migrations through the Supabase GitHub integration, so `supabase/migrations`
must stay as it is.

## Decision

`better-supabase baseline` builds a local cache of the migrated and seeded
state and loads it into an empty stack. The artifact is a pg-delta plan from
an empty catalog to the migrated catalog (`schema.sql`), a data dump of the
tables the migrations changed (`data.sql`, with the
`supabase_migrations.schema_migrations` rows), a serialized catalog snapshot,
a per-kind digest of policies, triggers, grants, functions and extensions, and
a manifest. `--with-seed` adds the same for the seeded state plus a tarball of
the bucket objects. The folder name is a hash of the migration files, the
better-supabase, Supabase CLI and Postgres versions and the artifact format.

`apply` picks the artifact that holds the most migrations, requires every held
migration to be unedited and every other migration to sort after them, loads
the SQL with `psql` in one transaction, runs `supabase migration up` for the
newer files and restores or runs the seeds. On any mismatch it logs the reason
and replays everything. `verify` restores into a fresh stack and compares the
pg-delta plan to the stored catalog, the digests and the row counts, and
`build --verify` runs it.

Starting without migrations and seeds uses the CLI's environment overrides
(`SUPABASE_DB_MIGRATIONS_ENABLED=false`, `SUPABASE_DB_SEED_ENABLED=false`), so
no CLI change is needed to use the feature.

Files: `packages/better-supabase/src/cli/baseline/*`,
`src/cli/commands/baseline.ts`, the manifest entry and
`apps/docs/content/docs/(reference)/cli/baseline.mdx`.

## Alternatives considered

- A `pg_dump` custom archive of the schema: the dump orders objects by
  dependency but cannot be compared with the migrated catalog, and extension
  members and grants restore differently. The pg-delta plan restores through
  the same engine that `db diff` uses and can be verified with it.
- A physical `PGDATA` snapshot swapped into the native stack (option C). It
  skips the DDL load, which is 5 to 11 seconds of the apply here and scales
  with the number of schema objects, so it is the route to under 10 seconds.
  It depends on the CLI's data directory layout and is left as a follow-up.
- Squashing the migrations: it rewrites the history that the hosted
  integration reads.

## Consequences

Measured locally (CentraKit snapshot, 3 runs): the empty start takes 6
seconds and `apply --with-seed` 8 to 11 seconds, 14 to 17 seconds in total
against 28 seconds for the default start. The target of 15 seconds is met on a
fast laptop at the median and is not guaranteed on a 2 vCPU runner; the
benchmark workflow measures that and the numbers belong in the pull request.
The artifact is only valid for the same Postgres and CLI versions, so CI must
build it on the runner image the shards use. Quirks handled: extension-owned
tables, pgmq queues and their rows, and platform tables that only
`supabase_admin` can write.

Upstream proposals for the Supabase CLI: have an empty start also skip the
upload of `objects_path` files, and later add `supabase db restore --from` so
the load needs no `psql`. Revisit when the CLI adds either.
