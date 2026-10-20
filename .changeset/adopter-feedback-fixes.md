---
"better-supabase": minor
---

Fixes and additions from adopter feedback.

New API:

- `matchDbError(error, matchers)` maps a `DbError` kind to a value, for `orThrow` factories.
- `paginate({ withCount: true })` returns `total` on offset and cursor pages and narrows its type to `number`. On a cursor page after the first, it sends one extra request to count the matching rows.
- `db.$buckets.<name>` is each bucket registered with `betterSupabase.buckets()`, connected to `db.$storage`. The type follows `$with()`, `$withoutPlugins()` and the `db`, `sql` and `admin()` repositories of `createServer(betterSupabase)`, and `db.$storage` on a server `Db` now uses the caller's Storage client. Every framework adapter (`next`, `hono`, `orpc`, `edge`, `mcp`, `astro`, `sveltekit`, `react-router`, `solid-start`, `tanstack-start` and `expo`) carries the registry through a new trailing `B` type parameter, so `ctx.db.$buckets.<name>` is typed in handlers, actions and routes. `ctx.db.$storage` and `ctx.db.$buckets` now work on request contexts.
- `better-supabase/testing` adds `scopedSeed`, `withRollback` and `TestUser.context`. `asUser` also turns off supabase-js trace propagation.
- `gen` emits `WritableColumnOf` and `GeneratedColumnOf`, and the schema types export `WritableColumns` and `GeneratedColumns`.

Fixes:

- `update` with no columns to write reads the row and returns it, and `updateMany` returns a count of 0, instead of failing with `invalid_request`. A caller that relied on that error needs to check for empty data itself. A plugin that leaves the patch empty still gets `invalid_request`.
- `createMany`, `upsertMany`, `updateMany` and `deleteMany` type their result by `returning`. `orderBy` accepts `undefined` values and `updateMany` data no longer infers readonly arrays.
- The client follows auth state only when the supabase client has it.
- Text filter escaping and case rules are documented, and `$rpc` typing is pinned as stable API.

The generated column `memberships.tier_role` in `supabase/` is a repo-only test fixture and does not ship in the package.
