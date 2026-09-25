---
name: better-supabase
description: Query and write Supabase data with better-supabase's typed repositories, Results and codegen. Use when code imports better-supabase, when adding a table, query or mutation, or when a Supabase type is out of date.
---

# better-supabase

The data layer is `sb = defineSupabase(schema)` in `src/lib/supabase.ts`.
`schema` comes from the generated module (`config.output`, usually
`src/lib/supabase/generated.ts`). Never edit generated files.

## After a schema change

1. Write the migration (`supabase/schemas/*.sql` plus `supabase db diff`, or `supabase migration new`).
2. `supabase db reset` (or apply the migration).
3. `pnpm better-supabase gen`, then fix the type errors it surfaces.
4. CI runs `better-supabase gen --check`; commit the generated files.

## Querying

Get `db` from the request context, never from a global client, so RLS applies:

- Next.js: `const { db } = await next.server()`, `next.route(...)`, `next.action(...)`
- Next.js Cache Components: keep layouts synchronous; read `next.session()` in a `'use cache: private'` function inside `<Suspense>`, pass the promise to `<SessionProvider>` and read it with `useSession()`
- Hono: `c.var.db` after `bs.middleware()`
- oRPC: `context.db` after `bs.middleware()`
- Edge Functions: `bs.handler((request, { db }) => ...)`
- Browser: `browser.db`, or the hooks from `createHooks<typeof browser>()`

```ts
const result = await db.customers.findMany({
  select: ['id', 'name'],
  where: { status: 'active', notes: { some: { kind: 'call' } } },
  include: { organization: { select: ['name'] } },
  orderBy: { name: 'asc' },
  limit: 20,
});
if (!result.ok) return result; // DbError: kind, message, status, code
const customers = result.value;
```

- Methods return a `Result`, and database errors never throw. Use `.orThrow()` only where an exception is really wanted.
- Column names use the configured casing (`casing: 'camel'` means `organizationId`). Raw escape hatches (`$client`, `$sql`) use database names.
- Writes: `create`, `createMany`, `update(id, patch)`, `updateMany`, `upsert`, `delete`. Plugins (timestamps, soft delete, tenant, actor) fill their columns, so don't set them by hand.
- Handlers may return a `Result` directly. Adapters turn errors into RFC 9457 Problem Details with the right status.
- Server-only admin access: `server.admin()`. Only use it for trusted jobs, never for a user's request.

## Don't

- Don't create supabase-js clients by hand, and don't read cookies yourself. Use the adapters.
- Don't add `declare module` augmentation for types; everything comes from `schema`.
- Don't catch and swallow `DbError`; return it, or map it with `mapDbError`.

Docs: https://bettersupabase.com/docs (each page is also at `/llms.txt`).
