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
- Objects in `auth`, `storage` or other Supabase-managed schemas, except
  policies and triggers whose function lives in your own schema.
- Object kinds pg-delta doesn't track (casts, operators, text search
  configurations). Their SQL also goes in `supabase/schemas/_custom/` so
  dependent objects still resolve; `--strict-coverage` fails until it does.

Read every generated grant. pg-delta writes the full privilege state, so a new
table can come with grants to `anon` you didn't intend; `090_grants.sql` is
where the fixture's grants live.

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

`[experimental] stack = true` runs the stack without a Docker daemon (on a
machine with Docker it still uses containers), one stack per checkout, so git
worktrees can run side by side. Each worktree uses the ports in
`config.toml`, so stop one stack before starting another on the same ports.

- `supabase status` rejects `-o env` and `-o json`. Use
  `supabase status --env` (add `--output-format json` for JSON); it has no
  `JWT_SECRET`, and the testing helpers fall back to the CLI default.
- `SUPABASE_EXPERIMENTAL_STACK=0` runs one command on the Docker backend, for
  example to compare a failure. The two backends keep separate databases, so
  reset after switching.
- The Realtime kit's private-channel integration tests fail on the native
  stack while they pass on the Docker backend; check them on both before
  changing `src/realtime`.

## Integration tests leave objects behind

The integration suite creates functions and tables in the local database (for
example `better_supabase.tenant_entitlements`). Run `pnpm supabase:reset`
before `supabase db lint` or a schema export.
