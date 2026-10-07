# Database

The local stack in `supabase/` is a test fixture: the examples, the integration
suite and codegen all run against it. `supabase/schemas` is the source of
truth, and `supabase/migrations` holds reviewed migrations generated from it
by pg-delta (`docs/decisions/0006-pgdelta-and-native-stack.md`).

## Changing the schema

1. Edit or add a file in `supabase/schemas`. pg-delta orders the files by
   dependency, so the numbers in the names are for reading only.
2. Run `pnpm supabase:sync <name>` and review the new migration. The stack can
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
module through the sync on a second stack (ports 56420 to 56422) when the
Supabase CLI and Docker are available.

The `900_better_supabase_*` files in `supabase/schemas` and
`supabase/better-supabase-data` are SQL modules that `better-supabase sql sync`
writes from `apps/examples/nextjs` (its `sql.dir` points at the fixture). Never
edit them by hand. When a change touches one of those modules, run
`pnpm --filter @better-supabase/example-nextjs exec better-supabase sql sync`,
then `pnpm supabase:sync <name>`, and `sql data` from the same folder when the
data files changed. The example's `gen:check` fails while they are stale.

Managed block defaults follow the repo standard (hashed tokens, Vault secrets,
`text` ids, the module's CloudEvents sources). A shape that only an existing app
needs belongs in its adopt config, never in a managed default. When an adopter
needs a weaker value, add it to `src/sql/migration-options.ts`, so the config
accepts it in `mode: "adopt"` only and doctor warns about it (BS314).

Read every generated grant. pg-delta writes the full privilege state, so a new
table can come with grants to `anon` you didn't intend; `090_grants.sql` is
where the fixture's grants live.

When `pnpm supabase:sync` writes the same migration after every reset, look
for an expression Postgres rewrites. `x between a and b` inside an `and`
chain comes back from the catalog as `x >= a and x <= b`, so the diff never
converges; write the comparisons out (`usernameCheck` in
`src/sql/modules/profiles.ts`).

The access contract in `045_access_contract.sql` must answer `can_user` for
the configured `sql.modules.access.options.scope` (`organization` by
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

## The native stack

The fixture runs on the Docker backend. In a sandbox without Docker, prefix
the stack commands with `SUPABASE_EXPERIMENTAL_STACK=1` to use the Supabase
CLI's native stack (ADR 0006 says why it isn't committed). It runs one stack
per checkout with the ports in `config.toml`, so stop one before starting
another.

- Its `supabase status` rejects `-o env` and `-o json`; use
  `supabase status --env`. The Docker backend rejects `--env`, which is why
  CI and `scripts/env-local.ts` keep `-o env`.
- On CLI 2.119.0 its Realtime refuses or times out private-channel joins, so
  the Realtime block and PermDock topic integration tests fail there. Run them
  on the Docker backend.
- The two backends keep separate databases, so reset after switching.

## Integration tests leave objects behind

The integration suite creates functions and tables in the local database (for
example `better_supabase.tenant_entitlements`). Run `pnpm supabase:reset`
before `supabase db lint` or a schema export.
