# Database

The local stack in `supabase/` is a test fixture: the examples, the integration
suite and codegen all run against it. `supabase/schemas` is the source of
truth, and `supabase/migrations` holds reviewed migrations generated from it.

## Changing the schema

1. Edit the file in `supabase/schemas`. A new file goes into `schema_paths` in
   `supabase/config.toml`, after everything it depends on.
2. Stop the stack (`pnpm supabase:stop`). The project uses the migra diff
   engine, which reads `supabase/schemas` only while the stack is stopped.
3. Run `pnpm supabase:diff <name>` and review the new migration.
4. Start the stack, run `pnpm supabase:reset`, `pnpm supabase:test` and
   `pnpm test:integration`, then `pnpm db:gen`.

## What the diff misses

Add these to the migration by hand, below a comment that says so:

- Revokes, schema `usage` grants and function `execute` grants. Without the
  revokes, a new table keeps the default privileges, which give `anon` and
  `authenticated` full access.
- Data: `insert` into `rbac.role_permissions` or `storage.buckets`.
- Role settings and `notify pgrst`.

Read every generated policy. migra rewrites `$'` inside a string literal, so a
regular expression that ends in `$'` comes out as `;` and a line break.

## Checking that nothing changed

A pg-delta export compares grants, comments and triggers as well as tables:

```bash
pnpm exec supabase db schema declarative generate --experimental --local --output-dir /tmp/before
# change the schema, then reset
pnpm exec supabase db schema declarative generate --experimental --local --output-dir /tmp/after
diff -r /tmp/before /tmp/after
```

The export changes nothing in the repo. Don't add `[experimental.pgdelta]` to
`config.toml`: pg-delta ignores `schema_paths` and orders files itself.

## Integration tests leave objects behind

The integration suite creates functions and tables in the local database (for
example `better_supabase.tenant_entitlements`). Run `pnpm supabase:reset`
before `supabase db lint` or a schema export.
