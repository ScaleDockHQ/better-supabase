---
name: better-supabase
description: Query and write Supabase data with better-supabase's typed repositories, Results and codegen. Use when code imports better-supabase, when adding a table, query or mutation, when a Supabase type is out of date, or after upgrading better-supabase.
---

# better-supabase

The data layer is `betterSupabase = defineSupabase(schema)` in `src/lib/supabase/index.ts`.
`schema` comes from the generated module (`config.output`, usually
`src/lib/supabase/generated.ts`). Never edit generated files.

The `better-supabase` command ships in the `better-supabase` package, so
`pnpm better-supabase <command>` works once the package is installed. There
is no separate CLI package to add.

## Workflow: change the schema

1. Write the migration: edit `supabase/schemas/*.sql`, then run
   `supabase db schema declarative sync -f <name>` (pg-delta;
   `supabase db diff -f <name>` when `config.toml` has no
   `[experimental.pgdelta] enabled = true`), or `supabase migration new` for
   data and role settings.
2. For a new table in an exposed schema, in the same file: `enable row level
security`, a policy per role and command the app uses, and an index on
   every column a policy filters by. Write tenant checks as
   `organization_id in (select better_supabase.member_org_ids())`, which
   Postgres runs once per statement, not `has_org_role(organization_id)`,
   which runs once per row. List the table in `expose` in
   `better-supabase.config.ts` and run `pnpm better-supabase sql add grants`:
   new tables get no Data API grants on their own.
3. Apply it with `supabase db reset` (or `supabase migration up`).
4. Run `pnpm better-supabase gen`, then fix the type errors it surfaces.
5. Run `pnpm better-supabase doctor` and fix every error it reports (RLS off,
   missing policies, missing grants, unindexed foreign keys, drift).
6. Commit the generated files. CI runs `better-supabase gen --check`, which
   prints a diff of each stale file.

Done when `gen --check` and `doctor` exit 0 and the project typechecks.

## Workflow: add a query or mutation

1. Get `db` from the request context (see below), never from a global client,
   so RLS applies.
2. Call the repository method and return or branch on its `Result`.
3. If a plugin owns a column (timestamps, soft delete, tenant, actor), leave
   it out of the input. See [references/plugins.md](references/plugins.md).
4. Cover the rule with an RLS test as a real user (the
   `better-supabase-testing` skill).

Done when the call typechecks without casts, the error path returns the
`DbError` (not a thrown exception), and a test shows another tenant's rows
stay hidden.

## Workflow: after upgrading better-supabase

1. Run `pnpm better-supabase codemod <version> --dry-run` for each minor
   version you crossed (`codemod` without a name lists them), then without
   `--dry-run`, and fix the lines it lists for review.
2. Run `pnpm better-supabase sql upgrade`, so the kit modules get the
   release's SQL and any forward steps land in a migration, then write a
   migration from the changed files.
3. Run `pnpm better-supabase gen` and commit the result. Since 0.3, a
   composite foreign key such as `(customer_id, organization_id)` is named
   after the remaining column (`customer`); set `tables.<name>.relations` in
   the config to keep an old relation name.
4. Run `pnpm better-supabase skills install --check` and reinstall the skills
   when it reports them stale.
5. Read the release's breaking changes in
   https://github.com/ScaleDockHQ/better-supabase/blob/main/CHANGELOG.md
   (guides live under https://bettersupabase.com/docs/migration). For 0.3: time values are
   `Temporal` (see below), `--db-url` is gone, `doctor --format json` is
   `doctor --json`, `BetterResultShape` is `BetterResultValue`, and an
   exhaustive `switch` over the `invalid` auth reason needs an `'actor'` case.

Done when `gen --check`, `doctor` and the typecheck pass.

## Where `db` comes from

Name the definition `betterSupabase` (in `lib/supabase/index.ts`) and every runtime instance `bs` (`lib/supabase/server.ts`, `lib/supabase/client.ts`, or the Hono, oRPC or Edge Function entry).

- Next.js: `const { db } = await bs.context()`, `bs.route(...)`, `bs.action(...)`
- Next.js Cache Components: keep layouts synchronous; read `bs.session()` in a `'use cache: private'` function inside `<Suspense>`, pass the promise to `<SessionProvider>` and read it with `useSession()`
- Hono: `c.var.db` after `bs.middleware()`
- oRPC: `context.db` after `bs.middleware()`
- Edge Functions: `bs.handler((request, { db }) => ...)`
- Browser: `bs.db`, or the hooks from `createHooks<typeof bs>()`

For who the caller is (sessions, claims, OAuth clients, agents, scopes), use
the `better-supabase-auth` skill.

## Querying

```ts
const result = await db.customers.findMany({
  select: ["id", "name"],
  where: { status: "active", notes: { some: { kind: "call" } } },
  include: { organization: { select: ["name"] } },
  orderBy: { name: "asc" },
  limit: 20,
});
if (!result.ok) return result; // DbError: kind, message, status, code
const customers = result.data;
```

- Methods return a `Result`, and database errors never throw. Use `.orThrow()` only where an exception is really wanted.
- Column names use the configured casing (`casing: 'camel'` means `organizationId`). Raw escape hatches (`$client`, and `queryRaw` on the `better-supabase/postgres` clients) use database names.
- Writes: `create`, `createMany`, `update(id, patch)`, `updateMany`, `upsert`, `delete`.
- Page lists with a cursor: `paginate({ after: null, size: 25, orderBy })`, then pass `nextCursor` back as `after` with the same `orderBy` and `where`. Use `page` numbers only when users jump to a page and need a total, and `paginate({ offset, limit, count: 'exact' })` when the caller already has an offset; both return the rows and the total in one request.
- Handlers may return a `Result` directly. Adapters turn errors into RFC 9457 Problem Details with the right status.
- Server-only admin access: `bs.admin()`. Only use it for trusted jobs, never for a user's request.
- PostgREST has no multi-request transactions. Put multi-step writes in a database function (`db.$rpc()`) or use `postgres.transaction()` on the server.

## Time values

- With `codecs: { timestamptz: 'instant' }` in the config, `timestamptz` columns decode to `Temporal.Instant` and `timestamp` columns to `Temporal.PlainDateTime`, with microseconds. Without the codec they stay ISO strings.
- `now` options, job and webhook timestamps and `bucket.sweep({ olderThan })` take `Temporal` values. Auth's `now` stays in epoch milliseconds.
- On Node 24, Safari and other runtimes without `Temporal`, add `temporal-polyfill` and `import "temporal-polyfill/global"` once at startup. Without it, calls that need `Temporal` return an `unexpected` `DbError` that names the import.
- Use TypeScript 6 or 7; 5.9 has no Temporal lib.

## CLI in scripts and CI

- No command takes a connection string as an argument. Set `$DATABASE_URL` or `source.dbUrl`, or pipe it in with `--db-url-stdin`.
- `--json` prints one JSON document on stdout: the result, or Problem Details with a `code` on failure. `--yes` and `CI` turn prompts off.
- Exit codes: 0 success, 1 a failure or finding (`--check` drift, doctor errors), 2 a usage, config or environment problem. Each error code is listed at https://bettersupabase.com/docs/cli/errors.

## Don't

- Don't create supabase-js clients by hand, and don't read cookies yourself. Use the adapters.
- Don't add `declare module` augmentation for types; everything comes from `schema`.
- Don't catch and swallow `DbError`; return it, or map it with `mapDbError`.
- Don't cast rows (`as Customer`). If a type is wrong, the schema or the generated file is out of date: rerun `gen`.
- Don't convert `Temporal` values to `Date` to compare them; use `.equals()` or `Temporal.Instant.compare`.

## When something fails

See [references/troubleshooting.md](references/troubleshooting.md) for each
`DbError` kind and the usual cause.

## Docs

https://bettersupabase.com/docs. Every page is also served as Markdown at
`https://bettersupabase.com/docs/<path>.md`, and
https://bettersupabase.com/llms.txt lists them all.

For Supabase itself (Auth, Storage, RLS, Postgres performance), install
Supabase's skills next to these: `npx skills add supabase/agent-skills`.
