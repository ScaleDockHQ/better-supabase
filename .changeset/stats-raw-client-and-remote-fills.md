---
"better-supabase": minor
---

Request stats now count the raw `ctx.supabase` client and remote cache
fills. While `debug` collects, each PostgREST, RPC, Storage and Edge Function
request the context's `supabase` client sends is a call on the request's
stats, named after its table, `name()`, `storage/<bucket>` or
`functions/<name>`; Auth calls don't count. A `'use cache: remote'` fill
called through `bsb.remote()` records on the request that called it, where
before it recorded nothing. With a request recorder, `ctx.db` keeps its own
PostgREST client instead of reusing `ctx.supabase`, so no call is counted
twice.
