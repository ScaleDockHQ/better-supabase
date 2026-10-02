---
name: better-supabase
description: Query and write Supabase data with better-supabase's typed repositories, Results and codegen. Use when code imports better-supabase, when adding a table, query or mutation, or when a Supabase type is out of date.
---

# better-supabase

The data layer is `sb = defineSupabase(schema)` in `src/lib/supabase.ts`.
`schema` comes from the generated module (`config.output`, usually
`src/lib/supabase/generated.ts`). Never edit generated files.

## Workflow: change the schema

1. Write the migration (`supabase/schemas/*.sql` plus `supabase db diff`, or
   `supabase migration new`).
2. Apply it with `supabase db reset` (or `supabase migration up`).
3. Run `pnpm better-supabase gen`, then fix the type errors it surfaces.
   The command comes from the `@better-supabase/cli` dev dependency.
4. Run `pnpm better-supabase doctor` and fix every error it reports (RLS off,
   missing policies, unindexed foreign keys, drift).
5. Commit the generated files. CI runs `better-supabase gen --check`.

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

## Where `db` comes from

- Next.js: `const { db } = await next.server()`, `next.route(...)`, `next.action(...)`
- Next.js Cache Components: keep layouts synchronous; read `next.session()` in a `'use cache: private'` function inside `<Suspense>`, pass the promise to `<SessionProvider>` and read it with `useSession()`
- Hono: `c.var.db` after `bs.middleware()`
- oRPC: `context.db` after `bs.middleware()`
- Edge Functions: `bs.handler((request, { db }) => ...)`
- Browser: `browser.db`, or the hooks from `createHooks<typeof browser>()`

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
- Column names use the configured casing (`casing: 'camel'` means `organizationId`). Raw escape hatches (`$client`, `$sql`) use database names.
- Writes: `create`, `createMany`, `update(id, patch)`, `updateMany`, `upsert`, `delete`.
- Handlers may return a `Result` directly. Adapters turn errors into RFC 9457 Problem Details with the right status.
- Server-only admin access: `server.admin()`. Only use it for trusted jobs, never for a user's request.
- PostgREST has no multi-request transactions. Put multi-step writes in a database function (`db.$rpc()`) or use `postgres.transaction()` on the server.

## Don't

- Don't create supabase-js clients by hand, and don't read cookies yourself. Use the adapters.
- Don't add `declare module` augmentation for types; everything comes from `schema`.
- Don't catch and swallow `DbError`; return it, or map it with `mapDbError`.
- Don't cast rows (`as Customer`). If a type is wrong, the schema or the generated file is out of date: rerun `gen`.

## When something fails

See [references/troubleshooting.md](references/troubleshooting.md) for each
`DbError` kind and the usual cause.

## Docs

https://bettersupabase.com/docs. Every page is also served as Markdown at
`https://bettersupabase.com/docs/<path>.md`, and
https://bettersupabase.com/llms.txt lists them all.
