---
"better-supabase": minor
---

The oRPC middleware returns refreshed or cleared session cookies on a denied call, and nested middleware resolves the request once. A cookie session refreshed early that hits a network failure keeps the user until the token expires, instead of resolving as `anon`. A malformed support cookie reads as no cookie instead of throwing, and clearing session cookies at old scopes sends the no-store headers. Storage `exists` returns `false` only for 400 and 404; a denied or failed check is an error. The `otel` plugin records `db.$rpc` calls as `EXECUTE <function>` spans.

`server.context(request)` returns the same context for repeat calls on one request. Support sessions reuse the target's claims for up to a minute, refreshes are kept per project and capped, and `next` invalidation decides between `updateTag` and `revalidateTag` once per mutation. Connected buckets cap their signed-URL cache at 500 entries and list sibling folders four at a time, vector buckets send batches four at a time, and anon and service queries with custom headers skip building a full supabase-js client. MCP servers reuse a user's visible tool list for the list's `ttlMs`.
