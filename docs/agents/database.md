# Database

The local stack in `supabase/` is a test fixture: the examples, the integration
suite and codegen all run against it. `supabase/schemas` is the source of
truth, and `supabase/migrations` holds reviewed migrations generated from it
by pg-delta (`docs/decisions/0006-pgdelta-and-native-stack.md`).

The history starts at one pg-delta baseline (ADR 0027). After pulling a
change that resets it, run `pnpm supabase:reset`; a stack migrated with the
old history lists the old migrations as remote-only.

## Layout

`supabase/schemas` uses the layout `supabase db schema declarative generate`
writes: one file per object at `<schema>/<kind>/<object>.sql`, for example
`public/tables/customers.sql` or `rbac/functions/authorize.sql`. A table's
file holds its grants, comments, policies and triggers, and a function's
file holds its revokes and grants. Extensions are in `_cluster/extensions/`,
types in `<schema>/types/`, and the `storage.objects` policies in
`storage/tables/objects.sql`. The SQL module files are in
`_better_supabase/` (see below).

## Changing the schema

1. Edit the object's file, or add one at `<schema>/<kind>/<object>.sql`.
   pg-delta orders the files by dependency, so a file never has to sort
   before the objects it uses.
2. Run `pnpm supabase:diff <name>` and review the new migration. The stack can
   keep running: the sync diffs the files against the migration history in a
   shadow database, not against the live one.
3. Run `pnpm supabase:reset`, `pnpm supabase:test` and `pnpm test:integration`,
   then `pnpm db:gen`.

`database.yml` runs the same sync and fails when it writes a migration, so a
schema edit without its migration never reaches `main`.

## What the diff misses

pg-delta captures tables, views, functions, triggers, policies, grants and
comments. Put these in a hand-written migration instead:

- Data: `insert` into `rbac.role_permissions` or `storage.buckets`. A data
  statement inside `supabase/schemas` is an error.
- Role settings (`alter role ... set`) and `notify pgrst`.
- Extensions in a schema pg-delta doesn't manage (`pgmq`, or `extensions`).
  `sql sync` writes a module's extensions that no migration creates into a
  `_better_supabase_extensions.sql` migration stamped before the schema
  migration you generate next, and `sql data` refuses to run while one is
  missing. Doctor BS321 warns about an extension no migration creates.
- Event triggers under `-s <schemas>`: they belong to no schema, so a
  filtered sync drops them. The module data files repeat them, and doctor
  BS323 reports one the database or the migrations lack.
- Objects in `auth`, `storage` or other Supabase-managed schemas, except
  policies and triggers whose function lives in your own schema.
- Object kinds pg-delta doesn't track (casts, operators, text search
  configurations). Their SQL also goes in `supabase/schemas/_custom/` so
  dependent objects still resolve; `--strict-coverage` fails until it does.

pg-delta also loads `supabase/schemas/_custom/` into its shadow database and
then rejects any managed table that has rows, so `_custom/` can't hold data
either. The SQL modules write their rows and role settings to
`supabase/better-supabase-data/` instead, and `better-supabase sql data`
turns them into a migration stamped after the newest one.
`tests/integration/pgdelta-roundtrip.integration.test.ts` runs every block
module through the sync on a second, legacy Docker stack (ports 56420 to 56422) when the Supabase CLI and Docker are available.

The `900_better_supabase_*` files in `supabase/schemas/_better_supabase` and
`supabase/better-supabase-data` are SQL modules that `better-supabase sql sync`
writes from `apps/examples/nextjs` (its `sql.dir` points at
`supabase/schemas/_better_supabase`). Never
edit them by hand. When a change touches one of those modules, run
`pnpm --filter @better-supabase/example-nextjs exec better-supabase sql sync`,
then `pnpm supabase:diff <name>`, and `sql data` from the same folder when the
data files changed. The example's `gen:check` fails while they are stale.

Managed block defaults follow the repo standard (hashed tokens, Vault secrets,
`text` ids, the module's CloudEvents sources). A shape that only an existing app
needs belongs in its adopt config, never in a managed default. When an adopter
needs a weaker value, add it to `src/sql/migration-options.ts`, so the config
accepts it in `mode: "adopt"` only and doctor warns about it (BS314).

Read every generated grant. pg-delta writes the full privilege state, so a new
table can come with grants to `anon` you didn't intend. Each fixture table
grants to the roles it needs in its own file; there is no bulk
`grant ... on all tables in schema`.

The fixture's own rows and role settings (RBAC role permissions, the
`customer-logos` and `avatars` buckets, the PostgREST aggregates setting)
are in the `_fixture_data.sql` migration. A new one goes in a new
hand-written migration.

When `pnpm supabase:diff` writes the same migration after every reset, look
for an expression Postgres rewrites. `x between a and b` inside an `and`
chain comes back from the catalog as `x >= a and x <= b`, so the diff never
converges; write the comparisons out (`usernameCheck` in
`src/sql/modules/profiles.ts`).

The access contract (`better_supabase/functions/can_user.sql` and the other
`better_supabase/functions/` files it calls) must answer `can_user` for
the configured `blocks.access.options.scope` (`organization` by
default) as well as `tenant`. The invitations module rechecks the inviter
with that scope, and a contract that answers only `tenant` rejects every
acceptance as `INVITATION_INVITER_REVOKED`.

## Checking that nothing changed

A pg-delta export compares grants, comments and triggers as well as tables:

```bash
pnpm exec supabase db schema declarative generate --local --output-dir /tmp/before
# change the schema, then reset
pnpm exec supabase db schema declarative generate --local --output-dir /tmp/after
diff -r /tmp/before /tmp/after
```

The export changes nothing in the repo; never point it at `supabase/schemas`.

## The stack engine

The fixture runs on the Supabase CLI's stack engine (`[experimental] stack =
true` in `config.toml`, ADR 0032). `pnpm supabase:start` creates the stack on
the native runtime, without Docker. The runtime is fixed when a stack is
created, and a plain `supabase start` picks Docker when it is running.

- The engine keeps one stack per checkout and branch, with its own ports and
  database, so two worktrees run side by side. Switching branches opens
  another stack: run `pnpm supabase:start` and `pnpm supabase:reset` again.
- Nothing may hardcode a port. `pnpm supabase:start` runs `pnpm env:local`,
  and code reads `SUPABASE_URL` and `SUPABASE_DB_URL`
  (`tests/integration/stack-env.ts` in the integration suite). `pnpm test:integration` and `pnpm db:gen` load
  `.env.development.local`.
- `supabase status --env --output-format json` prints the URLs and keys.
  `SUPABASE_EXPERIMENTAL_STACK=0` turns the legacy Docker engine back on;
  its status needs `-o json` instead, and `scripts/env-local.ts` reads both.
- Its Realtime denies the private-channel joins in three tests (two in
  `realtime.integration.test.ts`, one in `access-policies`), on every
  runtime. They skip when `SUPABASE_RUNTIME` names a stack engine runtime,
  and the CI `realtime` job runs them on the legacy engine.
- On the native runtime, `pg_net` reaches the host at `127.0.0.1`, not
  `host.docker.internal`.
- Services start on first request and stop when idle; `supabase start --eager`
  starts all of them and turns the idle stop off.
- A stack keeps running after its shell exits. `supabase stack list` shows
  every stack on the machine, `supabase stop` stops the current one and
  `supabase stop --stack-id <id>` or `--all` stops others.

## Integration tests leave objects behind

The integration suite creates functions and tables in the local database (for
example `better_supabase.tenant_entitlements`). Run `pnpm supabase:reset`
before `supabase db lint` or a schema export.
