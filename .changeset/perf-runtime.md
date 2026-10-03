---
"better-supabase": minor
---

Faster request path in the core runtime.

- `connect()` costs the same for any number of tables: every connection shares
  one prototype of table getters, and repositories are built on first access.
- For a signed-in user, `ctx.db` (and `dbFor()`) on the server runs on a bare
  PostgREST client, so requests that only query data no longer build the
  Realtime, Storage and Auth clients. `ctx.supabase` and `ctx.db.$client`
  still return the full supabase-js client, built when first read.
  `better-supabase` now depends on `@supabase/postgrest-js` at the version
  supabase-js uses.
- Default selections, rendered select strings, column lookups, unique keys,
  invalidation targets and the tables a query spec reads are computed once per
  table or spec instead of on every call. Plugin hooks, tenant resolution and
  claim paths are resolved once, and `mutation` and `error` payloads are only
  built when someone listens.
- Row decoding and paging copy each row once instead of spreading and deleting
  keys in loops.
- Bucket connections take `{ cacheSignedUrls: true }` to reuse a signed URL
  until shortly before it expires. The cache belongs to the connection.
- Outside production, the event hub warns once when an event collects more
  than 50 handlers, which usually means a missing unsubscribe.

`invalidationTargets()` now returns a frozen `readonly string[]`.
